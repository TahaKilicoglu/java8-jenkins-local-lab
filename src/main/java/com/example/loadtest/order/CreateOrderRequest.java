package com.example.loadtest.order;

import javax.validation.constraints.Min;
import javax.validation.constraints.NotNull;

public class CreateOrderRequest {
    @NotNull @Min(1) private Long customerId;
    @NotNull @Min(1) private Long productId;
    @NotNull @Min(1) private Integer quantity;
    public Long getCustomerId() { return customerId; }
    public void setCustomerId(Long customerId) { this.customerId = customerId; }
    public Long getProductId() { return productId; }
    public void setProductId(Long productId) { this.productId = productId; }
    public Integer getQuantity() { return quantity; }
    public void setQuantity(Integer quantity) { this.quantity = quantity; }
}
