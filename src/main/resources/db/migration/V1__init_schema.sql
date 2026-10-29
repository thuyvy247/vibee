-- Vibee - schema v1 (MySQL 8.0.16+)
-- Thời gian lưu theo UTC. Tiền: DECIMAL(15,2).

CREATE TABLE users (
    id            BIGINT       NOT NULL AUTO_INCREMENT,
    email         VARCHAR(255) NOT NULL,
    password_hash VARCHAR(100) NOT NULL,
    full_name     VARCHAR(150) NOT NULL,
    phone         VARCHAR(20)  NULL,
    role          VARCHAR(20)  NOT NULL DEFAULT 'ATTENDEE',  -- ATTENDEE | ORGANIZER | STAFF | ADMIN
    status        VARCHAR(20)  NOT NULL DEFAULT 'ACTIVE',    -- ACTIVE | LOCKED
    created_at    DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at    DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    CONSTRAINT uk_users_email UNIQUE (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE refresh_tokens (
    id         BIGINT      NOT NULL AUTO_INCREMENT,
    user_id    BIGINT      NOT NULL,
    token_hash CHAR(64)    NOT NULL,                         -- SHA-256 của refresh token, không lưu token gốc
    expires_at DATETIME(6) NOT NULL,
    revoked    BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    CONSTRAINT uk_refresh_token_hash UNIQUE (token_hash),
    CONSTRAINT fk_refresh_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    INDEX idx_refresh_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE events (
    id           BIGINT       NOT NULL AUTO_INCREMENT,
    organizer_id BIGINT       NOT NULL,
    title        VARCHAR(255) NOT NULL,
    description  TEXT         NULL,
    venue        VARCHAR(255) NOT NULL,
    banner_url   VARCHAR(500) NULL,
    start_time   DATETIME(6)  NOT NULL,
    end_time     DATETIME(6)  NOT NULL,
    status       VARCHAR(20)  NOT NULL DEFAULT 'DRAFT',     -- DRAFT | PENDING | PUBLISHED | ENDED | CANCELLED
    created_at   DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at   DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    CONSTRAINT fk_events_organizer FOREIGN KEY (organizer_id) REFERENCES users (id),
    CONSTRAINT chk_events_time CHECK (end_time > start_time),
    INDEX idx_events_status_start (status, start_time),
    INDEX idx_events_organizer (organizer_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE ticket_types (
    id                 BIGINT        NOT NULL AUTO_INCREMENT,
    event_id           BIGINT        NOT NULL,
    name               VARCHAR(100)  NOT NULL,              -- VIP, Standard...
    price              DECIMAL(15,2) NOT NULL,
    total_quantity     INT           NOT NULL,
    available_quantity INT           NOT NULL,
    sale_start         DATETIME(6)   NOT NULL,
    sale_end           DATETIME(6)   NOT NULL,
    max_per_order      INT           NOT NULL DEFAULT 5,
    version            INT           NOT NULL DEFAULT 0,    -- optimistic locking
    created_at         DATETIME(6)   NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at         DATETIME(6)   NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    CONSTRAINT fk_tt_event FOREIGN KEY (event_id) REFERENCES events (id) ON DELETE CASCADE,
    CONSTRAINT chk_tt_price CHECK (price >= 0),
    CONSTRAINT chk_tt_qty CHECK (available_quantity >= 0 AND available_quantity <= total_quantity),
    CONSTRAINT chk_tt_sale CHECK (sale_end > sale_start),
    CONSTRAINT uk_tt_event_name UNIQUE (event_id, name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE orders (
    id           BIGINT        NOT NULL AUTO_INCREMENT,
    order_code   CHAR(16)      NOT NULL,                    -- mã hiển thị / dùng làm vnp_TxnRef
    user_id      BIGINT        NOT NULL,
    status       VARCHAR(20)   NOT NULL DEFAULT 'PENDING',  -- PENDING | PAID | EXPIRED | CANCELLED
    total_amount DECIMAL(15,2) NOT NULL,
    expires_at   DATETIME(6)   NOT NULL,
    created_at   DATETIME(6)   NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at   DATETIME(6)   NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    CONSTRAINT uk_orders_code UNIQUE (order_code),
    CONSTRAINT fk_orders_user FOREIGN KEY (user_id) REFERENCES users (id),
    INDEX idx_orders_user (user_id, created_at),
    INDEX idx_orders_expire (status, expires_at)            -- phục vụ job quét đơn hết hạn
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE order_items (
    id             BIGINT        NOT NULL AUTO_INCREMENT,
    order_id       BIGINT        NOT NULL,
    ticket_type_id BIGINT        NOT NULL,
    quantity       INT           NOT NULL,
    unit_price     DECIMAL(15,2) NOT NULL,                  -- chốt giá tại thời điểm mua
    PRIMARY KEY (id),
    CONSTRAINT fk_oi_order FOREIGN KEY (order_id) REFERENCES orders (id) ON DELETE CASCADE,
    CONSTRAINT fk_oi_tt FOREIGN KEY (ticket_type_id) REFERENCES ticket_types (id),
    CONSTRAINT chk_oi_qty CHECK (quantity > 0),
    INDEX idx_oi_order (order_id),
    INDEX idx_oi_tt (ticket_type_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE payments (
    id           BIGINT        NOT NULL AUTO_INCREMENT,
    order_id     BIGINT        NOT NULL,
    provider     VARCHAR(20)   NOT NULL DEFAULT 'VNPAY',
    txn_ref      VARCHAR(64)   NOT NULL,                    -- UNIQUE để xử lý IPN trùng (idempotency)
    provider_txn_no VARCHAR(64) NULL,                       -- mã giao dịch phía VNPay
    amount       DECIMAL(15,2) NOT NULL,
    status       VARCHAR(20)   NOT NULL DEFAULT 'PENDING',  -- PENDING | SUCCESS | FAILED
    raw_response TEXT          NULL,
    paid_at      DATETIME(6)   NULL,
    created_at   DATETIME(6)   NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    CONSTRAINT uk_payments_txn_ref UNIQUE (txn_ref),
    CONSTRAINT fk_payments_order FOREIGN KEY (order_id) REFERENCES orders (id),
    INDEX idx_payments_order (order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE tickets (
    id             BIGINT      NOT NULL AUTO_INCREMENT,
    order_item_id  BIGINT      NOT NULL,
    event_id       BIGINT      NOT NULL,                    -- denormalize để check-in kiểm tra nhanh đúng sự kiện
    code           CHAR(32)    NOT NULL,                    -- mã trong QR (random/UUID không dấu gạch)
    status         VARCHAR(20) NOT NULL DEFAULT 'VALID',    -- VALID | USED | CANCELLED
    checked_in_at  DATETIME(6) NULL,
    checked_in_by  BIGINT      NULL,
    created_at     DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    CONSTRAINT uk_tickets_code UNIQUE (code),
    CONSTRAINT fk_tickets_oi FOREIGN KEY (order_item_id) REFERENCES order_items (id),
    CONSTRAINT fk_tickets_event FOREIGN KEY (event_id) REFERENCES events (id),
    CONSTRAINT fk_tickets_staff FOREIGN KEY (checked_in_by) REFERENCES users (id),
    INDEX idx_tickets_oi (order_item_id),
    INDEX idx_tickets_event (event_id, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
