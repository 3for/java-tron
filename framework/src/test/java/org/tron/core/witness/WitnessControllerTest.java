package org.tron.core.witness;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.google.protobuf.ByteString;
import java.util.ArrayList;
import java.util.List;
import javax.annotation.Resource;
import org.junit.Test;
import org.tron.common.BaseTest;
import org.tron.common.TestConstants;
import org.tron.common.utils.ByteArray;
import org.tron.consensus.dpos.DposService;
import org.tron.consensus.dpos.DposSlot;
import org.tron.core.config.args.Args;

public class WitnessControllerTest extends BaseTest {

  @Resource
  private DposSlot dposSlot;


  static {
    Args.setParam(new String[]{"-d", dbPath()}, TestConstants.TEST_CONF);
  }

  @Test
  public void testWitnessSchedule() {
    DposService dposService = mock(DposService.class);
    when(dposService.getGenesisBlockTime())
        .thenReturn(chainBaseManager.getGenesisBlock().getTimeStamp());
    dposSlot.setDposService(dposService);
    List<ByteString> activeWitnesses = new ArrayList<>();
    chainBaseManager.getWitnessStore().getAllWitnesses()
        .forEach(witness -> activeWitnesses.add(witness.getAddress()));
    chainBaseManager.getWitnessStore().sortWitness(activeWitnesses,
        chainBaseManager.getDynamicPropertiesStore().allowWitnessSortOptimization());
    chainBaseManager.getWitnessScheduleStore().saveActiveWitnesses(activeWitnesses);

    // no witness produce block
    assertEquals(0, chainBaseManager.getHeadBlockNum());

    // DposService initializes the active schedule from the sorted witness store.
    assertTrue(activeWitnesses.size() > 6);
    assertEquals(activeWitnesses.get(0), dposSlot.getScheduledWitness(0));
    assertEquals(activeWitnesses.get(5), dposSlot.getScheduledWitness(5));
    assertEquals(activeWitnesses.get(6), dposSlot.getScheduledWitness(6));
    assertEquals(activeWitnesses.get(0),
        dposSlot.getScheduledWitness(activeWitnesses.size()));
    assertEquals(activeWitnesses.get(1),
        dposSlot.getScheduledWitness(activeWitnesses.size() + 1L));

    // test maintenance
    ByteString a =
        ByteString.copyFrom(ByteArray.fromHexString("41ec6525979a351a54fa09fea64beb4cce33ffbb7a"));
    ByteString b =
        ByteString.copyFrom(ByteArray.fromHexString("41fab5fbf6afb681e4e37e9d33bddb7e923d6132e5"));
    List<ByteString> w = new ArrayList<>();
    w.add(a);
    w.add(b);

    // update active witness
    chainBaseManager.getWitnessScheduleStore().saveActiveWitnesses(w);
    // now 2 active witnesses
    assertEquals(2, chainBaseManager.getWitnessScheduleStore().getActiveWitnesses().size());

    assertEquals(a, dposSlot.getScheduledWitness(0));
    assertEquals(b, dposSlot.getScheduledWitness(1));
    assertEquals(a, dposSlot.getScheduledWitness(2));
    assertEquals(b, dposSlot.getScheduledWitness(3));
  }
}
