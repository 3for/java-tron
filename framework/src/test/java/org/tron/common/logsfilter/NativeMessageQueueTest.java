package org.tron.common.logsfilter;

import java.nio.charset.StandardCharsets;
import java.util.concurrent.TimeUnit;
import org.junit.Assert;
import org.junit.Test;
import org.tron.common.logsfilter.nativequeue.NativeMessageQueue;
import org.tron.common.utils.PublicMethod;
import org.zeromq.SocketType;
import org.zeromq.ZContext;
import org.zeromq.ZMQ;

public class NativeMessageQueueTest {

  private static final String DATA_TO_SEND = "################";
  private static final String TOPIC = "testTopic";

  @Test
  public void invalidBindPort() {
    try {
      Assert.assertTrue(NativeMessageQueue.getInstance().start(-1111, 0));
    } finally {
      NativeMessageQueue.getInstance().stop();
    }
  }

  @Test
  public void invalidSendLength() {
    try {
      Assert.assertTrue(NativeMessageQueue.getInstance().start(0, -2222));
    } finally {
      NativeMessageQueue.getInstance().stop();
    }
  }

  @Test(timeout = 10_000)
  public void publishTriggerDeliversTopicAndData() {
    int bindPort = PublicMethod.chooseRandomPort();
    Assert.assertTrue(NativeMessageQueue.getInstance().start(bindPort, 0));

    try (ZContext context = new ZContext()) {
      try {
        ZMQ.Socket subscriber = context.createSocket(SocketType.SUB);
        Assert.assertTrue(subscriber.connect(String.format("tcp://localhost:%d", bindPort)));
        Assert.assertTrue(subscriber.subscribe(TOPIC));
        subscriber.setReceiveTimeOut(250);

        byte[] receivedTopic = null;
        byte[] receivedData = null;
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5);
        while (receivedTopic == null && System.nanoTime() < deadline) {
          NativeMessageQueue.getInstance().publishTrigger(DATA_TO_SEND, TOPIC);
          receivedTopic = subscriber.recv();
          if (receivedTopic != null) {
            receivedData = subscriber.recv();
          }
        }

        Assert.assertNotNull("subscriber did not receive the published topic", receivedTopic);
        Assert.assertNotNull("subscriber did not receive the published data", receivedData);
        Assert.assertEquals(TOPIC, new String(receivedTopic, StandardCharsets.UTF_8));
        Assert.assertEquals(DATA_TO_SEND, new String(receivedData, StandardCharsets.UTF_8));
      } finally {
        NativeMessageQueue.getInstance().stop();
      }
    }
  }
}
