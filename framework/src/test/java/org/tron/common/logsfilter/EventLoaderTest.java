package org.tron.common.logsfilter;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertSame;
import static org.junit.Assert.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.junit.Test;
import org.pf4j.PluginDescriptor;
import org.pf4j.PluginManager;
import org.pf4j.PluginWrapper;
import org.tron.common.logsfilter.trigger.BlockLogTrigger;
import org.tron.common.logsfilter.trigger.InternalTransactionPojo;
import org.tron.common.logsfilter.trigger.LogPojo;
import org.tron.common.logsfilter.trigger.TransactionLogTrigger;
import org.tron.common.logsfilter.trigger.Trigger;

public class EventLoaderTest {

  @Test
  public void launchNativeQueue() {
    EventPluginConfig config = new EventPluginConfig();
    config.setSendQueueLength(1000);
    config.setBindPort(5555);
    config.setUseNativeQueue(true);
    config.setPluginPath("pluginPath");
    config.setServerAddress("serverAddress");
    config.setDbConfig("dbConfig");
    assertEquals("pluginPath", config.getPluginPath());
    assertEquals("serverAddress", config.getServerAddress());
    assertEquals("dbConfig", config.getDbConfig());

    List<TriggerConfig> triggerConfigList = new ArrayList<>();

    TriggerConfig triggerConfig = new TriggerConfig();
    triggerConfig.setTriggerName("block");
    triggerConfig.setEnabled(true);
    triggerConfig.setTopic("topic");
    triggerConfig.setRedundancy(false);
    triggerConfig.setEthCompatible(false);
    triggerConfig.setSolidified(false);
    assertFalse(triggerConfig.isRedundancy());
    assertFalse(triggerConfig.isEthCompatible());
    assertFalse(triggerConfig.isSolidified());
    assertEquals("topic", triggerConfig.getTopic());
    triggerConfigList.add(triggerConfig);

    config.setTriggerConfigList(triggerConfigList);

    assertTrue(EventPluginLoader.getInstance().start(config));

    EventPluginLoader.getInstance().stopPlugin();
  }

  @Test
  public void testIsPluginVersionSupported() {
    assertEquals("3.0.0", EventPluginLoader.MIN_PLUGIN_VERSION);
    // last releases before fastjson removal — must be rejected
    assertFalse(checkVersion("1.0.0"));
    assertFalse(checkVersion("2.2.0"));
    assertFalse(checkVersion("2.9.9"));
    // 3.0.0 onward — must be accepted
    assertTrue(checkVersion("3.0.0"));
    assertTrue(checkVersion("3.1.5"));
    assertTrue(checkVersion("10.0.0"));
    // empty/null version — reject
    assertFalse(checkVersion(""));
    assertFalse(checkVersion(null));
  }

  private static boolean checkVersion(String version) {
    PluginManager pm = mock(PluginManager.class);
    PluginWrapper wrapper = mock(PluginWrapper.class);
    PluginDescriptor desc = mock(PluginDescriptor.class);
    when(pm.getPlugin("test")).thenReturn(wrapper);
    when(wrapper.getDescriptor()).thenReturn(desc);
    when(desc.getVersion()).thenReturn(version);
    return EventPluginLoader.isPluginVersionSupported(pm, "test");
  }

  @Test
  public void testBlockLogTrigger() {
    BlockLogTrigger blt = new BlockLogTrigger();
    List<String> transactionIds = Arrays.asList("tx-1", "tx-2");
    blt.setBlockHash("block-hash");
    blt.setBlockNumber(42L);
    blt.setTransactionSize(2L);
    blt.setLatestSolidifiedBlockNumber(40L);
    blt.setTimeStamp(123456L);
    blt.setTransactionList(transactionIds);
    blt.setRemoved(true);

    assertEquals(Trigger.BLOCK_TRIGGER_NAME, blt.getTriggerName());
    assertEquals("block-hash", blt.getBlockHash());
    assertEquals(42L, blt.getBlockNumber());
    assertEquals(2L, blt.getTransactionSize());
    assertEquals(40L, blt.getLatestSolidifiedBlockNumber());
    assertEquals(123456L, blt.getTimeStamp());
    assertSame(transactionIds, blt.getTransactionList());
    assertTrue(blt.isRemoved());
    assertEquals("triggerName: blockTrigger, timestamp: 123456, blockNumber: 42, "
        + "blockhash: block-hash, transactionSize: 2, latestSolidifiedBlockNumber: 40, "
        + "removed: true, transactionList: [tx-1, tx-2]", blt.toString());
  }

  @Test
  public void testTransactionLogTrigger() {
    TransactionLogTrigger tlt = new TransactionLogTrigger();
    List<InternalTransactionPojo> internalTransactions = new ArrayList<>();
    List<LogPojo> logs = new ArrayList<>();
    Map<String, Long> extensions = new HashMap<>();
    extensions.put("retryCount", 3L);

    tlt.setTransactionId("transaction-id");
    tlt.setBlockHash("block-hash");
    tlt.setBlockNumber(101L);
    tlt.setEnergyUsage(11L);
    tlt.setEnergyFee(12L);
    tlt.setOriginEnergyUsage(13L);
    tlt.setEnergyUsageTotal(14L);
    tlt.setNetUsage(15L);
    tlt.setNetFee(16L);
    tlt.setResult("SUCCESS");
    tlt.setContractAddress("contract-address");
    tlt.setContractType("TriggerSmartContract");
    tlt.setFeeLimit(17L);
    tlt.setContractCallValue(18L);
    tlt.setContractResult("contract-result");
    tlt.setFromAddress("from-address");
    tlt.setToAddress("to-address");
    tlt.setAssetName("asset-name");
    tlt.setAssetAmount(19L);
    tlt.setLatestSolidifiedBlockNumber(100L);
    tlt.setInternalTransactionList(internalTransactions);
    tlt.setData("deadbeef");
    tlt.setTransactionIndex(2);
    tlt.setCumulativeEnergyUsed(20L);
    tlt.setPreCumulativeLogCount(21L);
    tlt.setLogList(logs);
    tlt.setEnergyUnitPrice(22L);
    tlt.setExtMap(extensions);
    tlt.setRemoved(true);
    tlt.setTimeStamp(123456L);

    assertEquals(Trigger.TRANSACTION_TRIGGER_NAME, tlt.getTriggerName());
    assertEquals("transaction-id", tlt.getTransactionId());
    assertEquals("block-hash", tlt.getBlockHash());
    assertEquals(101L, tlt.getBlockNumber());
    assertEquals(11L, tlt.getEnergyUsage());
    assertEquals(12L, tlt.getEnergyFee());
    assertEquals(13L, tlt.getOriginEnergyUsage());
    assertEquals(14L, tlt.getEnergyUsageTotal());
    assertEquals(15L, tlt.getNetUsage());
    assertEquals(16L, tlt.getNetFee());
    assertEquals("SUCCESS", tlt.getResult());
    assertEquals("contract-address", tlt.getContractAddress());
    assertEquals("TriggerSmartContract", tlt.getContractType());
    assertEquals(17L, tlt.getFeeLimit());
    assertEquals(18L, tlt.getContractCallValue());
    assertEquals("contract-result", tlt.getContractResult());
    assertEquals("from-address", tlt.getFromAddress());
    assertEquals("to-address", tlt.getToAddress());
    assertEquals("asset-name", tlt.getAssetName());
    assertEquals(19L, tlt.getAssetAmount());
    assertEquals(100L, tlt.getLatestSolidifiedBlockNumber());
    assertSame(internalTransactions, tlt.getInternalTransactionList());
    assertEquals("deadbeef", tlt.getData());
    assertEquals(2, tlt.getTransactionIndex());
    assertEquals(20L, tlt.getCumulativeEnergyUsed());
    assertEquals(21L, tlt.getPreCumulativeLogCount());
    assertSame(logs, tlt.getLogList());
    assertEquals(22L, tlt.getEnergyUnitPrice());
    assertSame(extensions, tlt.getExtMap());
    assertTrue(tlt.isRemoved());
    assertEquals(123456L, tlt.getTimeStamp());
  }
}
