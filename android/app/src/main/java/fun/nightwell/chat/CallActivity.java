package fun.nightwell.chat;
import android.Manifest;
import android.app.Activity;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.webkit.*;
import android.widget.*;
import android.view.View;
import java.util.ArrayList;
public final class CallActivity extends Activity {
    private WebView web;
    private PermissionRequest waiting;
    @Override public void onCreate(Bundle b){
        super.onCreate(b);
        getWindow().setStatusBarColor(0xff080808);
        LinearLayout box=new LinearLayout(this); box.setOrientation(1);box.setBackgroundColor(0xff080808);
        Button close=new Button(this);close.setText("Завершить звонок");box.addView(close);
        close.setOnClickListener(v->finish());
        web=new WebView(this);box.addView(web,new LinearLayout.LayoutParams(-1,0,1));setContentView(box);
        web.setWebChromeClient(new WebChromeClient(){
            @Override public void onPermissionRequest(PermissionRequest req){
                runOnUiThread(()->{
                    if(!"https://chat.nightwell.fun".equals(req.getOrigin().toString())){
                        req.deny();return;
                    }
                    ArrayList<String> missing=new ArrayList<>();
                    for(String resource:req.getResources()){
                        if(PermissionRequest.RESOURCE_AUDIO_CAPTURE.equals(resource) &&
                            checkSelfPermission(Manifest.permission.RECORD_AUDIO)!=PackageManager.PERMISSION_GRANTED)
                            missing.add(Manifest.permission.RECORD_AUDIO);
                        if(PermissionRequest.RESOURCE_VIDEO_CAPTURE.equals(resource) &&
                            checkSelfPermission(Manifest.permission.CAMERA)!=PackageManager.PERMISSION_GRANTED)
                            missing.add(Manifest.permission.CAMERA);
                    }
                    if(!missing.isEmpty()){
                        waiting=req;
                        requestPermissions(missing.toArray(new String[0]),51);
                    }else grantMedia(req);
                });
            }
        });
        web.getSettings().setJavaScriptEnabled(true);
        web.getSettings().setDomStorageEnabled(true);
        web.getSettings().setAllowFileAccess(false);
        web.getSettings().setAllowContentAccess(false);
        web.getSettings().setMediaPlaybackRequiresUserGesture(false);
        String u=getIntent().getStringExtra("url");
        if(u!=null && u.startsWith("https://chat.nightwell.fun/calls/"))web.loadUrl(u);else finish();
    }
    private void grantMedia(PermissionRequest req){
        ArrayList<String> allowed=new ArrayList<>();
        for(String resource:req.getResources()){
            if(PermissionRequest.RESOURCE_AUDIO_CAPTURE.equals(resource) &&
                checkSelfPermission(Manifest.permission.RECORD_AUDIO)==PackageManager.PERMISSION_GRANTED)
                allowed.add(resource);
            if(PermissionRequest.RESOURCE_VIDEO_CAPTURE.equals(resource) &&
                checkSelfPermission(Manifest.permission.CAMERA)==PackageManager.PERMISSION_GRANTED)
                allowed.add(resource);
        }
        if(allowed.isEmpty())req.deny();
        else req.grant(allowed.toArray(new String[0]));
    }
    @Override public void onRequestPermissionsResult(int req,String[] p,int[] granted){
        super.onRequestPermissionsResult(req,p,granted);
        if(req==51 && waiting!=null){grantMedia(waiting);waiting=null;}
    }
    @Override public void onDestroy(){if(waiting!=null)waiting.deny();if(web!=null){web.loadUrl("about:blank");web.destroy();}super.onDestroy();}
}
