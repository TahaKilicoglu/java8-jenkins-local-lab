package com.example.loadtest.order;

public class OrderResponse {
    private final Long orderId;
    private final String status;
    public OrderResponse(Long orderId, String status) {
        this.orderId = orderId;
        this.status = status;
    }
    public Long getOrderId() { return orderId; }
    public String getStatus() { return status; }
}
