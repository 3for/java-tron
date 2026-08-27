package org.tron.common.logsfilter.capsule;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertSame;
import static org.junit.Assert.assertTrue;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import org.junit.Before;
import org.junit.Test;
import org.tron.common.bloom.Bloom;
import org.tron.protos.Protocol.TransactionInfo;

public class LogsFilterCapsuleTest {

  private LogsFilterCapsule capsule;

  @Before
  public void setUp() {
    capsule = new LogsFilterCapsule(0,
        "e58f33f9baf9305dc6f82b9f1934ea8f0ade2defb951258d50167028c780351f",
        new Bloom(), new ArrayList<>(), true, false);
  }

  @Test
  public void testSetAndGetLogsFilterCapsule() {
    Bloom bloom = new Bloom();
    List<TransactionInfo> transactions =
        Collections.singletonList(TransactionInfo.getDefaultInstance());

    capsule.setBlockNumber(42L);
    capsule.setBlockHash("updated-block-hash");
    capsule.setSolidified(false);
    capsule.setBloom(bloom);
    capsule.setRemoved(true);
    capsule.setTxInfoList(transactions);

    assertEquals(42L, capsule.getBlockNumber());
    assertEquals("updated-block-hash", capsule.getBlockHash());
    assertFalse(capsule.isSolidified());
    assertSame(bloom, capsule.getBloom());
    assertTrue(capsule.isRemoved());
    assertSame(transactions, capsule.getTxInfoList());
  }

}
