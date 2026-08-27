package org.tron.core.config.args;

import java.io.File;
import java.io.IOException;
import org.junit.Assert;
import org.junit.Test;
import org.tron.common.BaseMethodTest;
import org.tron.common.TestConstants;
import org.tron.common.parameter.CommonParameter;
import org.tron.common.utils.ReflectUtils;
import org.tron.core.net.TronNetService;
import org.tron.p2p.P2pConfig;

public class DynamicArgsTest extends BaseMethodTest {
  private DynamicArgs dynamicArgs;

  @Override
  protected void afterInit() {
    dynamicArgs = context.getBean(DynamicArgs.class);
  }

  @Test
  public void start() throws IOException {
    CommonParameter parameter = Args.getInstance();
    Assert.assertEquals(TestConstants.TEST_CONF, Args.getConfigFilePath());
    Assert.assertTrue(parameter.isDynamicConfigEnable());
    Assert.assertEquals(600, parameter.getDynamicConfigCheckInterval());

    dynamicArgs.init();
    File configFile = (File) ReflectUtils.getFieldObject(dynamicArgs, "configFile");
    Assert.assertNotNull(configFile);
    Assert.assertEquals(TestConstants.TEST_CONF, configFile.getName());
    Assert.assertEquals(0, (long) ReflectUtils.getFieldObject(dynamicArgs, "lastModified"));

    TronNetService tronNetService = context.getBean(TronNetService.class);
    ReflectUtils.setFieldValue(tronNetService, "p2pConfig", new P2pConfig());
    File config = new File(Args.getConfigFilePath());
    boolean created = false;
    try {
      if (!config.exists()) {
        created = config.createNewFile();
        Assert.assertTrue("Test configuration file was not created", created);
        dynamicArgs.run();
        Assert.assertTrue("Temporary test configuration file was not deleted", config.delete());
        created = false;
      }
      dynamicArgs.reload();
    } finally {
      try {
        dynamicArgs.close();
      } finally {
        if (created && config.exists()) {
          Assert.assertTrue("Temporary test configuration file was not deleted",
              config.delete() || !config.exists());
        }
      }
    }
  }
}
