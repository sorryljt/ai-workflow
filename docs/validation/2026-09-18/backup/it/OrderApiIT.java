package com.example.demo.app.order;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/** 集成测试：真实 Postgres（Testcontainers），需要 Docker。由 failsafe 在 verify 阶段执行。 */
@Testcontainers
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class OrderApiIT {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    @Autowired
    TestRestTemplate rest;

    @Autowired
    OrderRepository repository;

    @BeforeEach
    void clean() {
        repository.deleteAll();
    }

    @Test
    void createsOrderAndPersistsIt() {
        ResponseEntity<OrderResponse> res = rest.postForEntity("/orders",
                Map.of("orderNo", "NO-100", "unitPrice", 10, "quantity", 3, "discountRate", 1), OrderResponse.class);

        assertThat(res.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        assertThat(res.getBody().amount()).isEqualByComparingTo(new BigDecimal("30.00"));
        assertThat(repository.count()).isEqualTo(1);
    }

    @Test
    void roundsAmountHalfUpAndPersistsRoundedValue() {
        ResponseEntity<OrderResponse> res = rest.postForEntity("/orders",
                Map.of("orderNo", "NO-300", "unitPrice", "3.33", "quantity", 1, "discountRate", "0.5"),
                OrderResponse.class);

        assertThat(res.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        assertThat(res.getBody().amount()).isEqualByComparingTo(new BigDecimal("1.67"));
        assertThat(repository.findAll()).singleElement()
                .extracting(Order::getAmount)
                .satisfies(amount -> assertThat(amount).isEqualByComparingTo(new BigDecimal("1.67")));
    }

    @Test
    void duplicateOrderNoReturns409AndDoesNotInsert() {
        Map<String, Object> body = Map.of("orderNo", "NO-200", "unitPrice", 10, "quantity", 1, "discountRate", 1);
        rest.postForEntity("/orders", body, OrderResponse.class);

        ResponseEntity<String> second = rest.postForEntity("/orders", body, String.class);

        assertThat(second.getStatusCode()).isEqualTo(HttpStatus.CONFLICT);
        assertThat(repository.count()).isEqualTo(1);
    }

    @Test
    void firstRequestWithIdempotencyKeyPersistsKeyAndHash() {
        ResponseEntity<OrderResponse> res = postWithKey("k1", order("NO-400", 10, 3, 1), OrderResponse.class);

        assertThat(res.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        assertThat(res.getHeaders().getFirst("Idempotent-Replayed")).isNull();
        assertThat(repository.findAll()).singleElement().satisfies(o -> {
            assertThat(o.getIdempotencyKey()).isEqualTo("k1");
            assertThat(o.getRequestHash()).hasSize(64);
        });
    }

    @Test
    void repeatedKeyWithSameBodyReplaysFirstResultWithoutInsert() {
        ResponseEntity<OrderResponse> first = postWithKey("k1", order("NO-401", 10, 3, 1), OrderResponse.class);
        // 等值的不同写法（10 与 "10.00"）视为同一请求
        ResponseEntity<OrderResponse> second = postWithKey("k1",
                Map.of("orderNo", "NO-401", "unitPrice", "10.00", "quantity", 3, "discountRate", "1.0"), OrderResponse.class);

        assertThat(second.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        assertThat(second.getHeaders().getFirst("Idempotent-Replayed")).isEqualTo("true");
        assertThat(second.getBody()).isEqualTo(first.getBody());
        assertThat(repository.count()).isEqualTo(1);
    }

    @Test
    void concurrentRequestsWithSameKeyInsertOnce() throws Exception {
        int threads = 8;
        ExecutorService pool = Executors.newFixedThreadPool(threads);
        CountDownLatch start = new CountDownLatch(1);
        List<Future<ResponseEntity<OrderResponse>>> futures = new ArrayList<>();
        try {
            for (int i = 0; i < threads; i++) {
                Callable<ResponseEntity<OrderResponse>> call = () -> {
                    start.await();
                    return postWithKey("k2", order("NO-402", 10, 1, 1), OrderResponse.class);
                };
                futures.add(pool.submit(call));
            }
            start.countDown();
            List<ResponseEntity<OrderResponse>> results = new ArrayList<>();
            for (Future<ResponseEntity<OrderResponse>> f : futures) {
                results.add(f.get());
            }

            assertThat(results).allSatisfy(r -> assertThat(r.getStatusCode()).isEqualTo(HttpStatus.CREATED));
            assertThat(results).extracting(r -> r.getBody().id()).containsOnly(results.get(0).getBody().id());
            assertThat(repository.findByIdempotencyKey("k2")).isPresent();
            assertThat(repository.count()).isEqualTo(1);
        } finally {
            pool.shutdownNow();
        }
    }

    @Test
    void sameKeyWithDifferentBodyReturns422AndKeepsFirstOrder() {
        postWithKey("k1", order("NO-403", 10, 1, 1), OrderResponse.class);

        ResponseEntity<Map> res = postWithKey("k1", order("NO-403", 10, 2, 1), Map.class);

        assertThat(res.getStatusCode()).isEqualTo(HttpStatus.UNPROCESSABLE_ENTITY);
        assertThat(res.getBody()).containsEntry("error", "IDEMPOTENCY_KEY_REUSED");
        assertThat(repository.findAll()).singleElement()
                .extracting(Order::getAmount)
                .satisfies(amount -> assertThat(amount).isEqualByComparingTo(new BigDecimal("10.00")));
    }

    @Test
    void differentKeysWithSameOrderNoReturn409() {
        postWithKey("k1", order("NO-404", 10, 1, 1), OrderResponse.class);

        ResponseEntity<String> res = postWithKey("k3", order("NO-404", 10, 1, 1), String.class);

        assertThat(res.getStatusCode()).isEqualTo(HttpStatus.CONFLICT);
        assertThat(repository.count()).isEqualTo(1);
    }

    private static Map<String, Object> order(String orderNo, int unitPrice, int quantity, int discountRate) {
        return Map.of("orderNo", orderNo, "unitPrice", unitPrice, "quantity", quantity, "discountRate", discountRate);
    }

    private <T> ResponseEntity<T> postWithKey(String key, Map<String, Object> body, Class<T> type) {
        HttpHeaders headers = new HttpHeaders();
        headers.set("Idempotency-Key", key);
        return rest.postForEntity("/orders", new HttpEntity<>(body, headers), type);
    }
}
