# Vibee - database & entity

- `src/main/resources/db/migration/V1__init_schema.sql`: Flyway migration (MySQL 8.0.16+)
- `src/main/java/com/vibee/{enums,entity,repository}`: entity JPA + repository trừ/hoàn tồn kho

application.yml gợi ý:

```yaml
spring:
  jpa:
    hibernate.ddl-auto: validate   # để Flyway quản lý schema, Hibernate chỉ kiểm tra
    properties.hibernate.jdbc.time_zone: UTC
  flyway:
    enabled: true
```

Dependencies: spring-boot-starter-data-jpa, mysql-connector-j, flyway-core, flyway-mysql, lombok.
