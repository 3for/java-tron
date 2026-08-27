package org.tron.common.logsfilter.capsule;

import static org.junit.Assert.assertEquals;
import static org.tron.common.logsfilter.trigger.Trigger.CONTRACTLOG_TRIGGER_NAME;

import java.lang.reflect.Field;
import lombok.extern.slf4j.Slf4j;
import org.junit.Before;
import org.junit.Test;
import org.mockito.Mockito;
import org.tron.common.logsfilter.EventPluginLoader;
import org.tron.common.logsfilter.trigger.ContractLogTrigger;

@Slf4j
public class ContractLogTriggerCapsuleTest {

  private ContractLogTriggerCapsule capsule;

  @Before
  public void setUp() {
    ContractLogTrigger contractLogTrigger = new ContractLogTrigger();
    contractLogTrigger.setBlockNumber(0L);
    capsule = new ContractLogTriggerCapsule(contractLogTrigger);
    capsule.setLatestSolidifiedBlockNumber(0);
  }

  @Test
  public void testSetAndGetContractLogTrigger() throws Exception {
    capsule.setContractLogTrigger(capsule.getContractLogTrigger());
    assertEquals(CONTRACTLOG_TRIGGER_NAME, capsule.getContractLogTrigger().getTriggerName());

    EventPluginLoader loader = Mockito.mock(EventPluginLoader.class);
    Field instanceField = EventPluginLoader.class.getDeclaredField("instance");
    instanceField.setAccessible(true);
    EventPluginLoader originalInstance = (EventPluginLoader) instanceField.get(null);
    instanceField.set(null, loader);
    try {
      capsule.processTrigger();
      Mockito.verify(loader).postContractLogTrigger(capsule.getContractLogTrigger());
    } finally {
      instanceField.set(null, originalInstance);
    }
  }

}
