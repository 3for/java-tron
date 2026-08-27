package org.tron.common.logsfilter.capsule;

import static org.junit.Assert.assertNotNull;

import java.lang.reflect.Field;
import lombok.extern.slf4j.Slf4j;
import org.junit.Before;
import org.junit.Test;
import org.mockito.Mockito;
import org.tron.common.logsfilter.EventPluginLoader;
import org.tron.common.logsfilter.trigger.SolidityTrigger;

@Slf4j
public class SolidityTriggerCapsuleTest {

  private SolidityTriggerCapsule capsule;

  @Before
  public void setUp() {
    capsule = new SolidityTriggerCapsule(0);
    SolidityTrigger trigger = new SolidityTrigger();
    assertNotNull(trigger.toString());
    capsule.setSolidityTrigger(trigger);
    capsule.setTimeStamp(System.currentTimeMillis());
  }

  @Test
  public void testSetAndGetSolidityLogCapsule() throws Exception {
    capsule.setSolidityTrigger(capsule.getSolidityTrigger());
    capsule.setTimeStamp(capsule.getSolidityTrigger().getTimeStamp());

    EventPluginLoader loader = Mockito.mock(EventPluginLoader.class);
    Field instanceField = EventPluginLoader.class.getDeclaredField("instance");
    instanceField.setAccessible(true);
    EventPluginLoader originalInstance = (EventPluginLoader) instanceField.get(null);
    instanceField.set(null, loader);
    try {
      capsule.processTrigger();
      Mockito.verify(loader).postSolidityTrigger(capsule.getSolidityTrigger());
    } finally {
      instanceField.set(null, originalInstance);
    }
  }

}
