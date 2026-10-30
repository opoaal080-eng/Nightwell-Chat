package fun.nightwell.chat;
import android.Manifest;
import android.app.Activity;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.webkit.*;
import android.widget.*;
import android.view.View;
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
                    if(android.os.Build.VERSION.SDK_INT>=23 && checkSelfPermission(Manifest.permission.RECORD_AUDIO)!=PackageManager.PERMISSION_GRANTED){
                        waiting=req;requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO},51);
                    }else req.grant(new String[]{PermissionRequest.RESOURCE_AUDIO_CAPTURE});
                });
            }
        });
        web.getSettings().setJavaScriptEnabled(true);
        web.getSettings().setMediaPlaybackRequiresUserGesture(false);
        String u=getIntent().getStringExtra("url");
        if(u!=null && u.startsWith("https://chat.nightwell.fun/calls/"))web.loadUrl(u);else finish();
    }
    @Override public void onRequestPermissionsResult(int req,String[] p,int[] granted){
        super.onRequestPermissionsResult(req,p,granted);
        if(req==51 && waiting!=null){if(granted.length>0 && granted[0]==PackageManager.PERMISSION_GRANTED)waiting.grant(new String[]{PermissionRequest.RESOURCE_AUDIO_CAPTURE}); else waiting.deny();waiting=null;}
    }
    @Override public void onDestroy(){if(waiting!=null)waiting.deny();if(web!=null){web.loadUrl("about:blank");web.destroy();}super.onDestroy();}
}
