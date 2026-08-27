package org.tron.core.event;

import static org.mockito.Mockito.mock;

import org.junit.Test;
import org.mockito.Mockito;
import org.tron.common.logsfilter.EventPluginLoader;
import org.tron.common.utils.ReflectUtils;
import org.tron.core.db.Manager;
import org.tron.core.services.event.BlockEventLoad;
import org.tron.core.services.event.EventService;
import org.tron.core.services.event.HistoryEventService;
import org.tron.core.services.event.RealtimeEventService;
import org.tron.core.services.event.SolidEventService;

public class EventServiceTest {

  @Test
  public void initAndCloseDelegateToEventServicesWhenPluginV1IsLoaded() {
    EventService eventService = new EventService();
    HistoryEventService historyEventService = mock(HistoryEventService.class);
    RealtimeEventService realtimeEventService = mock(RealtimeEventService.class);
    SolidEventService solidEventService = mock(SolidEventService.class);
    BlockEventLoad blockEventLoad = mock(BlockEventLoad.class);
    Manager manager = mock(Manager.class);
    EventPluginLoader instance = mock(EventPluginLoader.class);

    ReflectUtils.setFieldValue(eventService, "historyEventService", historyEventService);
    ReflectUtils.setFieldValue(eventService, "solidEventService", solidEventService);
    ReflectUtils.setFieldValue(eventService, "realtimeEventService", realtimeEventService);
    ReflectUtils.setFieldValue(eventService, "blockEventLoad", blockEventLoad);
    ReflectUtils.setFieldValue(eventService, "manager", manager);
    ReflectUtils.setFieldValue(eventService, "instance", instance);

    Mockito.when(manager.isEventPluginLoaded()).thenReturn(true);
    Mockito.when(instance.getVersion()).thenReturn(1);

    eventService.init();
    eventService.close();

    Mockito.verify(historyEventService).init();
    Mockito.verify(historyEventService).close();
    Mockito.verify(blockEventLoad).close();
    Mockito.verify(realtimeEventService).close();
    Mockito.verify(solidEventService).close();
  }
}
