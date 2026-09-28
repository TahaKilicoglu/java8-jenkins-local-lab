package com.example.loadtest.order;

import com.zaxxer.hikari.HikariDataSource;
import com.zaxxer.hikari.HikariPoolMXBean;
import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class PoolController {
    private final HikariDataSource dataSource;
    public PoolController(HikariDataSource dataSource) { this.dataSource = dataSource; }
    @GetMapping("/debug/pool")
    public Map<String, Integer> pool() {
        HikariPoolMXBean bean = dataSource.getHikariPoolMXBean();
        Map<String, Integer> result = new LinkedHashMap<String, Integer>();
        result.put("max", dataSource.getMaximumPoolSize());
        result.put("active", bean.getActiveConnections());
        result.put("idle", bean.getIdleConnections());
        result.put("total", bean.getTotalConnections());
        result.put("waiting", bean.getThreadsAwaitingConnection());
        return result;
    }
}
