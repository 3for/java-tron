package org.tron.core.metrics;

import java.util.UUID;
import org.junit.After;
import org.junit.Assert;
import org.junit.Before;
import org.junit.Test;
import org.tron.common.parameter.CommonParameter;

public class MetricsUtilTest {

  private boolean originalMetricsEnabled;
  private String key;

  @Before
  public void setUp() {
    originalMetricsEnabled = CommonParameter.getInstance().isNodeMetricsEnable();
    CommonParameter.getInstance().setNodeMetricsEnable(true);
    key = MetricsUtilTest.class.getName() + "." + UUID.randomUUID();
  }

  @After
  public void tearDown() {
    CommonParameter.getInstance().setNodeMetricsEnable(originalMetricsEnabled);
  }

  @Test
  public void testCounterInc() {
    MetricsUtil.counterInc(key);
    Assert.assertEquals(1, MetricsUtil.getCounter(key).getCount());
  }

  @Test
  public void testMeterMark() {
    MetricsUtil.meterMark(key);
    Assert.assertEquals(1, MetricsUtil.getMeter(key).getCount());
  }

  @Test
  public void testMeterMark2() {
    MetricsUtil.meterMark(key, 3);
    Assert.assertEquals(3, MetricsUtil.getMeter(key).getCount());
  }

  @Test
  public void testHistogramUpdate() {
    MetricsUtil.histogramUpdate(key, 7);
    Assert.assertEquals(1, MetricsUtil.getHistogram(key).getCount());
    Assert.assertEquals(7, MetricsUtil.getHistogram(key).getSnapshot().getMax());
  }
}
