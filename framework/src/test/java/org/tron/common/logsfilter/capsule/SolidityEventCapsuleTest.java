package org.tron.common.logsfilter.capsule;

import java.lang.reflect.Field;
import lombok.extern.slf4j.Slf4j;
import org.junit.Before;
import org.junit.Test;
import org.mockito.Mockito;
import org.tron.common.logsfilter.EventPluginLoader;
import org.tron.common.logsfilter.trigger.ContractEventTrigger;

@Slf4j
public class SolidityEventCapsuleTest {

  private SolidityEventCapsule capsule;

  @Before
  public void setUp() {
    ContractEventTrigger contractEventTrigger = new ContractEventTrigger();
    capsule = new SolidityEventCapsule(contractEventTrigger);
  }

  @Test
  public void testSetAndGetSolidityEventCapsule() throws Exception {
    capsule.setSolidityEventTrigger(capsule.getSolidityEventTrigger());

    EventPluginLoader loader = Mockito.mock(EventPluginLoader.class);
    Field instanceField = EventPluginLoader.class.getDeclaredField("instance");
    instanceField.setAccessible(true);
    EventPluginLoader originalInstance = (EventPluginLoader) instanceField.get(null);
    instanceField.set(null, loader);
    try {
      capsule.processTrigger();
      Mockito.verify(loader).postSolidityEventTrigger(capsule.getSolidityEventTrigger());
    } finally {
      instanceField.set(null, originalInstance);
    }
  }

}
