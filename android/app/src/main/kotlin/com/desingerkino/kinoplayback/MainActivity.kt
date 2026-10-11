package com.desingerkino.kinoplayback

import android.app.Presentation
import android.content.Context
import android.graphics.Color
import android.hardware.display.DisplayManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Display
import android.view.Gravity
import android.view.ViewGroup
import android.widget.FrameLayout
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.utils.EglUtils
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.webrtc.RendererCommon
import org.webrtc.SurfaceViewRenderer
import org.webrtc.VideoTrack

/**
 * KINO PLAYBACK activity + external display output.
 *
 * When Android exposes a secondary "presentation" display (USB-C DisplayPort
 * Alt Mode / HDMI adapter on phones that support it, some wireless display
 * modes), the app shows ONLY the WebRTC video track there via [Presentation]
 * — a clean feed. Plain screen mirroring (e.g. most Cast mirroring) does not
 * create a presentation display; in that case nothing is attached and the
 * Dart side reports NOT CONNECTED.
 */
class MainActivity : FlutterActivity() {
    private var displayManager: DisplayManager? = null
    private var presentation: FeedPresentation? = null
    private var sink: EventChannel.EventSink? = null
    private var track: VideoTrack? = null
    private var mirror = false
    private var rotation = 0f

    private val listener = object : DisplayManager.DisplayListener {
        override fun onDisplayAdded(displayId: Int) = onDisplaysChanged()
        override fun onDisplayRemoved(displayId: Int) = onDisplaysChanged()
        override fun onDisplayChanged(displayId: Int) = onDisplaysChanged()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val dm = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        displayManager = dm
        dm.registerDisplayListener(listener, Handler(Looper.getMainLooper()))

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kinoplayback/external_display")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(status())
                    "attach" -> result.success(
                        attach(
                            call.argument<String>("trackId"),
                            call.argument<String>("peerConnectionId"),
                            call.argument<Boolean>("mirror") ?: false,
                            (call.argument<Number>("rotation") ?: 0).toFloat(),
                        )
                    )
                    "transform" -> {
                        mirror = call.argument<Boolean>("mirror") ?: false
                        rotation = (call.argument<Number>("rotation") ?: 0).toFloat()
                        presentation?.applyTransform(mirror, rotation)
                        result.success(true)
                    }
                    "detach" -> {
                        detach()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "kinoplayback/external_display/events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    sink = events
                    events?.success(status())
                }

                override fun onCancel(arguments: Any?) {
                    sink = null
                }
            })
    }

    override fun onDestroy() {
        displayManager?.unregisterDisplayListener(listener)
        detach()
        super.onDestroy()
    }

    private fun presentationDisplay(): Display? =
        displayManager?.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION)?.firstOrNull()

    private fun status(): Map<String, Any?> {
        val d = presentationDisplay()
        val mode = d?.mode
        return mapOf(
            "connected" to (d != null),
            "active" to (d != null && presentation != null && track != null),
            "name" to d?.name,
            "width" to mode?.physicalWidth,
            "height" to mode?.physicalHeight,
            "kind" to "presentation",
        )
    }

    private fun onDisplaysChanged() {
        val d = presentationDisplay()
        val p = presentation
        if (d == null || (p != null && p.display.displayId != d.displayId)) {
            detach()
        }
        sink?.success(status())
    }

    private fun attach(trackId: String?, peerConnectionId: String?, mirror: Boolean, rotation: Float): Boolean {
        if (trackId == null) return false
        val plugin = FlutterWebRTCPlugin.sharedSingleton ?: return false
        val t = (plugin.getTrackForId(trackId, peerConnectionId) as? VideoTrack)
            ?: (plugin.getRemoteTrack(trackId) as? VideoTrack)
            ?: return false
        val d = presentationDisplay() ?: return false
        detach()
        val p = FeedPresentation(this, d)
        return try {
            p.show()
            p.attach(t)
            this.mirror = mirror
            this.rotation = rotation
            p.applyTransform(mirror, rotation)
            presentation = p
            track = t
            sink?.success(status())
            true
        } catch (e: Exception) {
            try {
                p.dismiss()
            } catch (_: Exception) {
            }
            false
        }
    }

    private fun detach() {
        val p = presentation
        val t = track
        presentation = null
        track = null
        if (p != null) {
            try {
                if (t != null) p.detach(t)
                p.dismiss()
            } catch (_: Exception) {
            }
        }
        sink?.success(status())
    }
}

/** Full-screen video on a secondary display. No Flutter UI is drawn there. */
class FeedPresentation(context: Context, display: Display) : Presentation(context, display) {
    private var renderer: SurfaceViewRenderer? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val root = FrameLayout(context)
        root.setBackgroundColor(Color.BLACK)
        val r = SurfaceViewRenderer(context)
        root.addView(
            r,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
                Gravity.CENTER,
            ),
        )
        setContentView(root)
        r.init(EglUtils.getRootEglBaseContext(), null)
        r.setScalingType(RendererCommon.ScalingType.SCALE_ASPECT_FIT)
        r.setEnableHardwareScaler(true)
        renderer = r
    }

    fun attach(track: VideoTrack) {
        renderer?.let { track.addSink(it) }
    }

    fun detach(track: VideoTrack) {
        renderer?.let {
            track.removeSink(it)
            it.release()
        }
        renderer = null
    }

    fun applyTransform(mirror: Boolean, rotation: Float) {
        renderer?.setMirror(mirror)
        renderer?.rotation = rotation
    }
}
