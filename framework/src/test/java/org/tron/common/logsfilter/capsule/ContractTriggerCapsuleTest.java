package org.tron.common.logsfilter.capsule;

import static com.google.common.collect.Lists.newArrayList;
import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.lang.reflect.Field;
import java.util.ArrayList;
import org.junit.Before;
import org.junit.Test;
import org.tron.common.logsfilter.EventPluginLoader;
import org.tron.common.logsfilter.trigger.ContractLogTrigger;
import org.tron.common.logsfilter.trigger.ContractTrigger;
import org.tron.common.runtime.vm.DataWord;
import org.tron.common.runtime.vm.LogInfo;
import org.tron.core.config.args.Args;

public class ContractTriggerCapsuleTest {

  private ContractTriggerCapsule capsule;

  private LogInfo logInfo;

  @Before
  public void setUp() {
    ContractTrigger contractTrigger = new ContractTrigger();
    contractTrigger.setBlockNumber(0L);
    contractTrigger.setRemoved(false);
    logInfo = new LogInfo(bytesToAddress(new byte[] {0x11}),
        newArrayList(new DataWord()), new byte[0]);
    contractTrigger.setLogInfo(logInfo);
    contractTrigger.setRawData(new RawData(null, null, null));
    contractTrigger.setAbi(contractTrigger.getAbi());
    capsule = new ContractTriggerCapsule(contractTrigger);

  }

  private byte[] bytesToAddress(byte[] address) {
    byte[] data = new byte[20];
    System.arraycopy(address, 0, data, 20 - address.length, address.length);
    return data;
  }

  @Test
  public void testSetAndGetContractTrigger() throws Exception {
    capsule.setContractTrigger(capsule.getContractTrigger());
    capsule.setBlockHash("e58f33f9baf9305dc6f82b9f1934ea8f0ade2defb951258d50167028c780351f");
    capsule.setLatestSolidifiedBlockNumber(0);
    assertEquals(0, capsule.getContractTrigger().getLatestSolidifiedBlockNumber());
    assertEquals("e58f33f9baf9305dc6f82b9f1934ea8f0ade2defb951258d50167028c780351f",
        capsule.getContractTrigger().getBlockHash());

    EventPluginLoader mockLoader = mock(EventPluginLoader.class);
    when(mockLoader.isContractLogTriggerEnable()).thenReturn(true);
    Field instanceField = EventPluginLoader.class.getDeclaredField("instance");
    instanceField.setAccessible(true);
    EventPluginLoader originalInstance = (EventPluginLoader) instanceField.get(null);
    instanceField.set(null, mockLoader);
    try {
      capsule.processTrigger();
      verify(mockLoader).postContractLogTrigger(any(ContractLogTrigger.class));
    } finally {
      instanceField.set(null, originalInstance);
    }
  }

  @Test
  public void testRemovedTriggerNotWrittenToSolidityMap() throws Exception {
    Args.getSolidityContractLogTriggerMap().clear();
    Args.getSolidityContractEventTriggerMap().clear();

    EventPluginLoader mockLoader = mock(EventPluginLoader.class);
    when(mockLoader.isSolidityLogTriggerEnable()).thenReturn(true);
    when(mockLoader.isSolidityEventTriggerEnable()).thenReturn(false);
    when(mockLoader.isContractLogTriggerEnable()).thenReturn(false);
    when(mockLoader.isContractEventTriggerEnable()).thenReturn(false);
    when(mockLoader.isSolidityLogTriggerRedundancy()).thenReturn(false);
    when(mockLoader.isContractLogTriggerRedundancy()).thenReturn(false);

    Field instanceField = EventPluginLoader.class.getDeclaredField("instance");
    instanceField.setAccessible(true);
    EventPluginLoader originalInstance = (EventPluginLoader) instanceField.get(null);
    instanceField.set(null, mockLoader);

    try {
      ContractLogTrigger trigger = new ContractLogTrigger();
      trigger.setRemoved(true);
      trigger.setBlockNumber(100L);
      trigger.setTransactionId("abc");
      trigger.setContractAddress("0x01");
      LogInfo logInfo = new LogInfo(new byte[0], new ArrayList<>(), new byte[0]);
      trigger.setLogInfo(logInfo);

      ContractTriggerCapsule capsule = new ContractTriggerCapsule(trigger);
      capsule.processTrigger();

      assertTrue(Args.getSolidityContractLogTriggerMap().isEmpty());
      assertTrue(Args.getSolidityContractEventTriggerMap().isEmpty());
    } finally {
      instanceField.set(null, originalInstance);
      Args.getSolidityContractLogTriggerMap().clear();
      Args.getSolidityContractEventTriggerMap().clear();
    }
  }

  @Test
  public void testLogInfo() {
    assertArrayEquals(new byte[0], logInfo.getClonedData());
    assertEquals(1, logInfo.getClonedTopics().size());
    assertArrayEquals(new byte[32], logInfo.getClonedTopics().get(0));
    assertEquals(1, logInfo.getHexTopics().size());
    assertTrue(logInfo.toString().contains("address=0000000000000000000000000000000000000011"));

    LogInfo empty = new LogInfo(null, null, null);
    assertArrayEquals(new byte[0], empty.getAddress());
    assertArrayEquals(new byte[0], empty.getData());
    assertTrue(empty.getTopics().isEmpty());
  }

}
