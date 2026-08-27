package org.tron.common.logsfilter.capsule;

import java.lang.reflect.Field;
import lombok.extern.slf4j.Slf4j;
import org.junit.Before;
import org.junit.Test;
import org.mockito.Mockito;
import org.tron.common.logsfilter.EventPluginLoader;
import org.tron.common.logsfilter.trigger.ContractLogTrigger;

@Slf4j
public class SolidityLogCapsuleTest {

  private SolidityLogCapsule capsule;

  @Before
  public void setUp() {
    ContractLogTrigger trigger = new ContractLogTrigger();
    capsule = new SolidityLogCapsule(trigger);
  }

  @Test
  public void testSetAndGetSolidityLogCapsule() throws Exception {
    capsule.setSolidityLogTrigger(capsule.getSolidityLogTrigger());

    EventPluginLoader loader = Mockito.mock(EventPluginLoader.class);
    Field instanceField = EventPluginLoader.class.getDeclaredField("instance");
    instanceField.setAccessible(true);
    EventPluginLoader originalInstance = (EventPluginLoader) instanceField.get(null);
    instanceField.set(null, loader);
    try {
      capsule.processTrigger();
      Mockito.verify(loader).postSolidityLogTrigger(capsule.getSolidityLogTrigger());
    } finally {
      instanceField.set(null, originalInstance);
    }
  }

}
