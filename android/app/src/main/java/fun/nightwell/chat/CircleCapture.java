package fun.nightwell.chat;

import android.graphics.Color;
import android.graphics.Outline;
import android.view.*;
import android.widget.*;
import androidx.camera.core.*;
import androidx.camera.lifecycle.ProcessCameraProvider;
import androidx.camera.video.*;
import androidx.camera.view.PreviewView;
import androidx.core.content.ContextCompat;
import java.io.File;

/** An in-chat, lifecycle-bound recorder. Persistent recording survives lens changes. */
final class CircleCapture {
    private final MainActivity host;
    private final FrameLayout overlay;
    private final PreviewView preview;
    private final TextView time;
    private final Button flash;
    private ProcessCameraProvider provider;
    private VideoCapture<Recorder> capture;
    private Preview previewUseCase;
    private Camera camera;
    private Recording recording;
    private File file;
    private boolean front=true,torch=false,closed=false,finishRequested=false;
    CircleCapture(MainActivity host) {
        this.host=host;
        overlay=new FrameLayout(host);
        // Transparent overlay leaves the conversation visible around the circular preview.
        preview=new PreviewView(host);
        preview.setImplementationMode(PreviewView.ImplementationMode.COMPATIBLE);
        preview.setScaleType(PreviewView.ScaleType.FILL_CENTER);
        preview.setOutlineProvider(new ViewOutlineProvider(){public void getOutline(View v,Outline o){o.setOval(0,0,v.getWidth(),v.getHeight());}});
        preview.setClipToOutline(true);
        int side=Math.min(host.getResources().getDisplayMetrics().widthPixels-host.dp(40),host.dp(340));
        FrameLayout.LayoutParams circle=new FrameLayout.LayoutParams(side,side,Gravity.CENTER);
        circle.bottomMargin=host.dp(90);overlay.addView(preview,circle);
        LinearLayout controls=new LinearLayout(host);controls.setGravity(Gravity.CENTER);
        Button cancel=button("✕", "Отменить запись");cancel.setOnClickListener(v->cancel());controls.addView(cancel);
        flash=button("ϟ", "Вспышка");flash.setOnClickListener(v->{if(camera!=null&&camera.getCameraInfo().hasFlashUnit()){torch=!torch;camera.getCameraControl().enableTorch(torch);flash.setTextColor(torch?Color.YELLOW:Color.WHITE);}});controls.addView(flash);
        Button flip=button("⟳", "Сменить камеру");flip.setOnClickListener(v->switchCamera());controls.addView(flip);
        Button done=button("↑", "Отправить кружок");done.setOnClickListener(v->finish());controls.addView(done);
        FrameLayout.LayoutParams buttons=new FrameLayout.LayoutParams(-1,host.dp(52),Gravity.BOTTOM);buttons.bottomMargin=host.dp(90);overlay.addView(controls,buttons);
        time=new TextView(host);time.setTextColor(Color.WHITE);time.setGravity(Gravity.CENTER);time.setText("Подготовка камеры");
        FrameLayout.LayoutParams timer=new FrameLayout.LayoutParams(-1,host.dp(40),Gravity.TOP);timer.topMargin=host.dp(70);overlay.addView(time,timer);
        host.addContentView(overlay,new ViewGroup.LayoutParams(-1,-1));
        var future=ProcessCameraProvider.getInstance(host);
        future.addListener(()->{try{if(closed)return;provider=future.get();
            Recorder recorder=new Recorder.Builder().setQualitySelector(QualitySelector.from(Quality.SD,FallbackStrategy.lowerQualityOrHigherThan(Quality.SD))).build();
            capture=VideoCapture.withOutput(recorder);capture.setTargetRotation(Surface.ROTATION_0);
            previewUseCase=new Preview.Builder().setTargetRotation(Surface.ROTATION_0).build();previewUseCase.setSurfaceProvider(preview.getSurfaceProvider());
            bind();start();
        }catch(Exception e){fail(e);}},ContextCompat.getMainExecutor(host));
    }
    private Button button(String text,String description){Button b=new Button(host);b.setText(text);b.setContentDescription(description);b.setTextColor(Color.WHITE);b.setBackground(host.shape(0x44333344));b.setLayoutParams(new LinearLayout.LayoutParams(host.dp(60),host.dp(48)));return b;}
    private void bind(){camera=provider.bindToLifecycle(host,front?CameraSelector.DEFAULT_FRONT_CAMERA:CameraSelector.DEFAULT_BACK_CAMERA,previewUseCase,capture);flash.setEnabled(camera.getCameraInfo().hasFlashUnit());}
    private void switchCamera(){if(provider==null||closed)return;try{
        CameraSelector next=front?CameraSelector.DEFAULT_BACK_CAMERA:CameraSelector.DEFAULT_FRONT_CAMERA;
        if(!provider.hasCamera(next))return;
        if(camera!=null)camera.getCameraControl().enableTorch(false);torch=false;flash.setTextColor(Color.WHITE);
        provider.unbind(previewUseCase,capture);front=!front;bind();
    }catch(Exception e){fail(e);}}
    @android.annotation.SuppressLint("MissingPermission")
    private void start() throws Exception {
        file=File.createTempFile("video_circle_",".mp4",host.getCacheDir());
        recording=capture.getOutput().prepareRecording(host,new FileOutputOptions.Builder(file).build())
            .withAudioEnabled().asPersistentRecording().start(ContextCompat.getMainExecutor(host),event->{
                if(event instanceof VideoRecordEvent.Start && finishRequested)finish();
                if(event instanceof VideoRecordEvent.Status){long seconds=event.getRecordingStats().getRecordedDurationNanos()/1_000_000_000L;time.setText(String.format(java.util.Locale.ROOT,"00:%02d / 01:00",seconds));if(seconds>=60)finish();}
                if(event instanceof VideoRecordEvent.Finalize){VideoRecordEvent.Finalize result=(VideoRecordEvent.Finalize)event;recording=null;
                    if(!closed && !result.hasError())host.sendCircle(file);
                    else {if(file!=null)file.delete();if(!closed)host.note("Не удалось сохранить кружок: "+result.getError());}
                    close();
                }
            });
    }
    void finish(){finishRequested=true;if(recording!=null)recording.stop();}
    void cancel(){closed=true;if(recording!=null)recording.stop();else if(file!=null)file.delete();close();}
    private void fail(Exception error){cancel();host.note("Камера: "+error.getMessage());}
    private void close(){closed=true;if(camera!=null)camera.getCameraControl().enableTorch(false);if(provider!=null&&capture!=null)provider.unbind(previewUseCase,capture);if(overlay.getParent() instanceof ViewGroup)((ViewGroup)overlay.getParent()).removeView(overlay);host.circleCapture=null;}
}
