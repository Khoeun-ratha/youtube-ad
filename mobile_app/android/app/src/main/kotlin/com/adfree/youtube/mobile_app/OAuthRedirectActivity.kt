package com.adfree.youtube.mobile_app

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * Receives Google's sign-in redirect (com.adfree.youtube.mobile_app:/oauth2redirect)
 * from the browser and hands it to the running MainActivity. CLEAR_TOP closes the
 * Custom Tab and delivers the URL through MainActivity.onNewIntent instead of
 * starting a second copy of the app.
 */
class OAuthRedirectActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        startActivity(
            Intent(this, MainActivity::class.java)
                .setData(intent.data)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        )
        finish()
    }
}
