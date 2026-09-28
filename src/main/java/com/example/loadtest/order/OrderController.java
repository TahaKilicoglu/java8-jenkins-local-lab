package com.example.loadtest.order;

import javax.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

@RestController
@RequestMapping("/api/orders")
public class OrderController {
    private static final Logger log = LogManager.getLogger(OrderController.class);
    private final OrderService service;
    public OrderController(OrderService service) { this.service = service; }
    @PostMapping
    public ResponseEntity<OrderResponse> create(@Valid @RequestBody CreateOrderRequest request) {
        OrderResponse response = service.create(request);
        log.info("order_created orderId={} customerId={}", response.getOrderId(), request.getCustomerId());
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }
    @GetMapping("/ping")
    public String ping() { return "OK"; }
    @GetMapping("/slow")
    public String slow() { service.slow(); return "OK"; }
}
