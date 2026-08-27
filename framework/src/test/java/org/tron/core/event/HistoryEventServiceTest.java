package org.tron.core.event;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.lang.reflect.Method;
import org.junit.Test;
import org.tron.common.logsfilter.EventPluginLoader;
import org.tron.common.utils.ReflectUtils;
import org.tron.core.ChainBaseManager;
import org.tron.core.capsule.BlockCapsule;
import org.tron.core.db.Manager;
import org.tron.core.services.event.BlockEventGet;
import org.tron.core.services.event.BlockEventLoad;
import org.tron.core.services.event.HistoryEventService;
import org.tron.core.services.event.RealtimeEventService;
import org.tron.core.services.event.SolidEventService;
import org.tron.core.services.event.bo.BlockEvent;
import org.tron.core.store.DynamicPropertiesStore;

public class HistoryEventServiceTest {

  @Test
  public void initAtHeadInitializesAllEventServices() {
    Fixture fixture = new Fixture();
    BlockCapsule.BlockId headId = mock(BlockCapsule.BlockId.class);
    when(fixture.instance.getStartSyncBlockNum()).thenReturn(0L);
    when(fixture.chainBaseManager.getHeadBlockId()).thenReturn(headId);

    fixture.service.init();

    verify(fixture.realtimeEventService).init();
    verify(fixture.blockEventLoad).init();
    verify(fixture.solidEventService).init();
  }

  @Test
  public void syncEventFlushesEachHistoricalBlockThenInitializesAtSolidHead() throws Exception {
    Fixture fixture = new Fixture();
    BlockEvent blockEvent = mock(BlockEvent.class);
    BlockCapsule.BlockId solidHeadId = mock(BlockCapsule.BlockId.class);
    when(fixture.instance.getStartSyncBlockNum()).thenReturn(1L);
    when(fixture.dynamicPropertiesStore.getLatestSolidifiedBlockNum()).thenReturn(2L);
    when(fixture.instance.isUseNativeQueue()).thenReturn(false);
    when(fixture.instance.isBusy()).thenReturn(false);
    when(fixture.blockEventGet.getBlockEvent(1L)).thenReturn(blockEvent);
    when(fixture.chainBaseManager.getBlockIdByNum(1L)).thenReturn(solidHeadId);
    ReflectUtils.setFieldValue(fixture.service, "thread", Thread.currentThread());

    Method syncEvent = HistoryEventService.class.getDeclaredMethod("syncEvent");
    syncEvent.setAccessible(true);
    syncEvent.invoke(fixture.service);

    verify(fixture.realtimeEventService).flush(blockEvent, false);
    verify(fixture.solidEventService).flush(blockEvent);
    verify(fixture.realtimeEventService).init();
    verify(fixture.blockEventLoad).init();
    verify(fixture.solidEventService).init();
  }

  private static class Fixture {

    private final HistoryEventService service = new HistoryEventService();
    private final EventPluginLoader instance = mock(EventPluginLoader.class);
    private final DynamicPropertiesStore dynamicPropertiesStore =
        mock(DynamicPropertiesStore.class);
    private final ChainBaseManager chainBaseManager = mock(ChainBaseManager.class);
    private final Manager manager = mock(Manager.class);
    private final SolidEventService solidEventService = mock(SolidEventService.class);
    private final RealtimeEventService realtimeEventService = mock(RealtimeEventService.class);
    private final BlockEventLoad blockEventLoad = mock(BlockEventLoad.class);
    private final BlockEventGet blockEventGet = mock(BlockEventGet.class);

    private Fixture() {
      when(manager.getChainBaseManager()).thenReturn(chainBaseManager);
      when(manager.getDynamicPropertiesStore()).thenReturn(dynamicPropertiesStore);
      ReflectUtils.setFieldValue(service, "instance", instance);
      ReflectUtils.setFieldValue(service, "manager", manager);
      ReflectUtils.setFieldValue(service, "solidEventService", solidEventService);
      ReflectUtils.setFieldValue(service, "realtimeEventService", realtimeEventService);
      ReflectUtils.setFieldValue(service, "blockEventLoad", blockEventLoad);
      ReflectUtils.setFieldValue(service, "blockEventGet", blockEventGet);
    }
  }
}
