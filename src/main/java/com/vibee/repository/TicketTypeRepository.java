package com.vibee.repository;

import com.vibee.entity.TicketType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface TicketTypeRepository extends JpaRepository<TicketType, Long> {

    /** Trừ tồn kho nguyên tử. Trả về 0 nghĩa là không đủ vé. */
    @Modifying(clearAutomatically = true)
    @Query("""
            UPDATE TicketType t
               SET t.availableQuantity = t.availableQuantity - :qty
             WHERE t.id = :id AND t.availableQuantity >= :qty
            """)
    int decreaseStock(@Param("id") Long id, @Param("qty") int qty);

    /** Hoàn tồn kho khi đơn hết hạn / bị hủy. */
    @Modifying(clearAutomatically = true)
    @Query("""
            UPDATE TicketType t
               SET t.availableQuantity = t.availableQuantity + :qty
             WHERE t.id = :id AND t.availableQuantity + :qty <= t.totalQuantity
            """)
    int increaseStock(@Param("id") Long id, @Param("qty") int qty);
}
