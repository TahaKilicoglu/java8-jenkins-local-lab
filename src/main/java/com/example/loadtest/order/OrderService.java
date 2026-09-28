package com.example.loadtest.order;

import javax.persistence.EntityManager;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class OrderService {
    private final OrderRepository repository;
    private final EntityManager entityManager;
    public OrderService(OrderRepository repository, EntityManager entityManager) {
        this.repository = repository;
        this.entityManager = entityManager;
    }
    @Transactional
    public OrderResponse create(CreateOrderRequest request) {
        Order order = new Order();
        order.setCustomerId(request.getCustomerId());
        order.setProductId(request.getProductId());
        order.setQuantity(request.getQuantity());
        Order saved = repository.save(order);
        return new OrderResponse(saved.getId(), "CREATED");
    }
    // PostgreSQL bağlantısını 200 ms meşgul tutan, kasıtlı yavaş demo.
    @Transactional(readOnly = true)
    public void slow() {
        entityManager.createNativeQuery("SELECT pg_sleep(0.2)").getSingleResult();
    }
}
