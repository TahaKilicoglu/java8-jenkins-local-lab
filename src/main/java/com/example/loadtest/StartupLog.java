package com.example.loadtest;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

@Component
public class StartupLog {
    private static final Logger log = LogManager.getLogger(StartupLog.class);

    @EventListener(ApplicationReadyEvent.class)
    public void onReady() {
        log.info("application_ready revision={}", System.getenv("APP_REVISION"));
    }
}
