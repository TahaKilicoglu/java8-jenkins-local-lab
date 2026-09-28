package com.example.loadtest;

import java.io.IOException;
import java.util.UUID;
import javax.servlet.FilterChain;
import javax.servlet.ServletException;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import org.apache.logging.log4j.ThreadContext;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

@Component
public class RequestIdFilter extends OncePerRequestFilter {
    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
            FilterChain chain) throws ServletException, IOException {
        String id = request.getHeader("X-Request-ID");
        if (id == null || !id.matches("[A-Za-z0-9_-]{1,64}")) {
            id = UUID.randomUUID().toString();
        }
        try {
            ThreadContext.put("requestId", id);
            response.setHeader("X-Request-ID", id);
            chain.doFilter(request, response);
        } finally {
            ThreadContext.remove("requestId");
        }
    }
}
