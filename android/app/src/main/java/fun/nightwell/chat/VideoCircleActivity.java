package fun.nightwell.chat;
import android.Manifest;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.drawable.GradientDrawable;
import android.os.*;
import android.view.*;
import android.widget.*;
import androidx.activity.ComponentActivity;
import androidx.camera.core.*;
import androidx.camera.lifecycle.ProcessCameraProvider;
import androidx.camera.video.*;
import androidx.camera.view.PreviewView;
import androidx.core.content.ContextCompat;
import androidx.core.content.FileProvider;
import java.io.File;

public final class VideoCircleActivity extends ComponentActivity {
    PreviewView preview;
    ProcessCameraProvider provider;
    VideoCapture<Recorder> capture;
    Camera camera;
    Recording recording;
    boolean front=true,torch=false,cancelled=false,stopping=false,held=false;
    TextView status;
    Button record,flip,light;
    File output;
    Handler handler=new Handler(Looper.getMainLooper());
    final Runnable limit=()->stopRecording(false);
    int dp(int n){return (int)(n*getResources().getDisplayMetrics().density);}
    Button button(String name,LinearLayout parent,Runnable action){
        Button b=new Button(this);b.setText(name);b.setAllCaps(false);parent.addView(b,new LinearLayout.LayoutParams(0,dp(56),1));b.setOnClickListener(v->action.run());return b;
    }
    @Override public void onCreate(Bundle state){
        super.onCreate(state);getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        LinearLayout root=new LinearLayout(this);root.setOrientation(1);root.setGravity(Gravity.CENTER);root.setPadding(dp(20),dp(20),dp(20),dp(20));root.setBackgroundColor(0xff080808);
        status=new TextView(this);status.setTextColor(-1);status.setTextSize(18);status.setGravity(Gravity.CENTER);status.setText("Видеокружок");root.addView(status);
        int side=Math.min(getResources().getDisplayMetrics().widthPixels-dp(40),dp(340));
        preview=new PreviewView(this);preview.setImplementationMode(PreviewView.ImplementationMode.COMPATIBLE);preview.setScaleType(PreviewView.ScaleType.FILL_CENTER);
        GradientDrawable circle=new GradientDrawable();circle.setColor(0xff202020);circle.setShape(GradientDrawable.OVAL);preview.setBackground(circle);preview.setClipToOutline(true);
        LinearLayout.LayoutParams image=new LinearLayout.LayoutParams(side,side);image.setMargins(0,dp(24),0,dp(24));root.addView(preview,image);
        LinearLayout controls=new LinearLayout(this);root.addView(controls);
        light=button("Вспышка",controls,()->{if(camera!=null&&camera.getCameraInfo().hasFlashUnit()){torch=!torch;camera.getCameraControl().enableTorch(torch);}});
        record=button("Запись",controls,()->{if(recording==null)startRecording();else stopRecording(false);});
        flip=button("Камера",controls,()->switchCamera());
        record.setOnLongClickListener(v->{if(recording==null){held=true;startRecording();}return true;});
        record.setOnTouchListener((v,e)->{if(held&&(e.getAction()==MotionEvent.ACTION_UP||e.getAction()==MotionEvent.ACTION_CANCEL)){held=false;stopRecording(e.getAction()==MotionEvent.ACTION_CANCEL);return true;}return false;});
        LinearLayout bottom=new LinearLayout(this);root.addView(bottom);button("Отмена",bottom,()->stopRecording(true));
        setContentView(root);record.setEnabled(false);
        if(checkSelfPermission(Manifest.permission.CAMERA)!=PackageManager.PERMISSION_GRANTED||checkSelfPermission(Manifest.permission.RECORD_AUDIO)!=PackageManager.PERMISSION_GRANTED)
            requestPermissions(new String[]{Manifest.permission.CAMERA,Manifest.permission.RECORD_AUDIO},77);
        else setup();
    }
    void setup(){
        com.google.common.util.concurrent.ListenableFuture<ProcessCameraProvider> future=ProcessCameraProvider.getInstance(this);
        future.addListener(()->{try{
            provider=future.get();
            Recorder recorder=new Recorder.Builder().setQualitySelector(QualitySelector.from(Quality.SD,FallbackStrategy.higherQualityOrLowerThan(Quality.SD))).build();
            capture=VideoCapture.withOutput(recorder);capture.setTargetRotation(Surface.ROTATION_0);
            if(!provider.hasCamera(CameraSelector.DEFAULT_FRONT_CAMERA))front=false;
            bind();record.setEnabled(true);
        }catch(Exception e){status.setText("Камера недоступна: "+e.getMessage());}},ContextCompat.getMainExecutor(this));
    }
    void bind(){
        Preview useCase=new Preview.Builder().setTargetRotation(Surface.ROTATION_0).build();useCase.setSurfaceProvider(preview.getSurfaceProvider());
        provider.unbindAll();camera=provider.bindToLifecycle(this,front?CameraSelector.DEFAULT_FRONT_CAMERA:CameraSelector.DEFAULT_BACK_CAMERA,useCase,capture);
        torch=false;light.setEnabled(camera.getCameraInfo().hasFlashUnit());
    }
    void switchCamera(){
        if(provider==null||stopping)return;boolean previous=front;
        try{
            CameraSelector next=front?CameraSelector.DEFAULT_BACK_CAMERA:CameraSelector.DEFAULT_FRONT_CAMERA;
            if(!provider.hasCamera(next))return;
            if(recording!=null)recording.pause();
            front=!front;bind();
            if(recording!=null)recording.resume();
        }catch(Exception e){
            front=previous;
            try{bind();if(recording!=null)recording.resume();}catch(Exception ignored){stopRecording(true);}
            status.setText("Не удалось переключить камеру");
        }
    }
    @android.annotation.SuppressLint({"MissingPermission","UnsafeOptInUsageError"})
    void startRecording(){
        if(capture==null||recording!=null||stopping)return;
        try{
            output=File.createTempFile("video_circle_",".mp4",getCacheDir());cancelled=false;
            recording=capture.getOutput().prepareRecording(this,new FileOutputOptions.Builder(output).setFileSizeLimit(49L*1024*1024).build())
                .withAudioEnabled().asPersistentRecording().start(ContextCompat.getMainExecutor(this),event->{
                    if(event instanceof VideoRecordEvent.Start){record.setText("Отправить");handler.postDelayed(limit,60000);}
                    if(event instanceof VideoRecordEvent.Status){long seconds=event.getRecordingStats().getRecordedDurationNanos()/1000000000L;status.setText(String.format(java.util.Locale.ROOT,"%02d:%02d",seconds/60,seconds%60));}
                    if(event instanceof VideoRecordEvent.Finalize){
                        handler.removeCallbacks(limit);recording=null;
                        VideoRecordEvent.Finalize done=(VideoRecordEvent.Finalize)event;
                        if(cancelled){if(output!=null)output.delete();finish();return;}
                        if(done.hasError()&&done.getError()!=VideoRecordEvent.Finalize.ERROR_FILE_SIZE_LIMIT_REACHED){status.setText("Запись не сохранена. Попробуй ещё раз.");if(output!=null)output.delete();stopping=false;record.setEnabled(true);record.setText("Запись");return;}
                        Intent result=new Intent().setData(FileProvider.getUriForFile(this,getPackageName()+".files",output)).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                        setResult(RESULT_OK,result);finish();
                    }
                });
        }catch(Exception e){status.setText("Не удалось начать запись: "+e.getMessage());}
    }
    void stopRecording(boolean cancel){
        cancelled=cancel;
        if(recording!=null){stopping=true;record.setEnabled(false);recording.stop();}
        else if(cancel)finish();
    }
    @Override public void onRequestPermissionsResult(int code,String[] permissions,int[] results){
        super.onRequestPermissionsResult(code,permissions,results);
        if(code==77&&checkSelfPermission(Manifest.permission.CAMERA)==PackageManager.PERMISSION_GRANTED&&checkSelfPermission(Manifest.permission.RECORD_AUDIO)==PackageManager.PERMISSION_GRANTED)setup();
        else status.setText("Разреши камеру и микрофон в настройках приложения");
    }
    @Override public void onBackPressed(){stopRecording(true);}
    @Override protected void onStop(){if(recording!=null&&!stopping)stopRecording(true);super.onStop();}
    @Override protected void onDestroy(){handler.removeCallbacksAndMessages(null);if(recording!=null)recording.close();if(provider!=null)provider.unbindAll();super.onDestroy();}
}
