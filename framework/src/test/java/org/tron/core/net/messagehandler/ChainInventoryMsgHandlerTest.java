package org.tron.core.net.messagehandler;

import java.util.ArrayList;
import java.util.LinkedList;
import java.util.List;
import org.junit.AfterClass;
import org.junit.Assert;
import org.junit.BeforeClass;
import org.junit.Test;
import org.tron.common.TestConstants;
import org.tron.common.utils.Pair;
import org.tron.core.capsule.BlockCapsule.BlockId;
import org.tron.core.config.Parameter.NetConstants;
import org.tron.core.config.args.Args;
import org.tron.core.exception.P2pException;
import org.tron.core.net.message.keepalive.PingMessage;
import org.tron.core.net.message.sync.ChainInventoryMessage;
import org.tron.core.net.peer.PeerConnection;

public class ChainInventoryMsgHandlerTest {

  @BeforeClass
  public static void init() {
    Args.setParam(new String[]{}, TestConstants.TEST_CONF);
  }

  @AfterClass
  public static void destroy() {
    Args.clearParam();
  }

  private ChainInventoryMsgHandler handler = new ChainInventoryMsgHandler();
  private PeerConnection peer = new PeerConnection();
  private ChainInventoryMessage msg = new ChainInventoryMessage(new ArrayList<>(), 0L);
  private List<BlockId> blockIds = new ArrayList<>();

  @Test
  public void testProcessMessage() throws Exception {
    P2pException notRequested = Assert.assertThrows(P2pException.class,
        () -> handler.processMessage(peer, msg));
    Assert.assertEquals(P2pException.TypeEnum.BAD_MESSAGE, notRequested.getType());
    Assert.assertEquals("not send syncBlockChainMsg", notRequested.getMessage());

    peer.setSyncChainRequested(new Pair<>(new LinkedList<>(), System.currentTimeMillis()));

    P2pException empty = Assert.assertThrows(P2pException.class,
        () -> handler.processMessage(peer, msg));
    Assert.assertEquals(P2pException.TypeEnum.BAD_MESSAGE, empty.getType());
    Assert.assertEquals("blockIds is empty", empty.getMessage());

    long size = NetConstants.SYNC_FETCH_BATCH_NUM + 2;
    for (int i = 0; i < size; i++) {
      blockIds.add(new BlockId());
    }
    msg = new ChainInventoryMessage(blockIds, 0L);

    P2pException tooMany = Assert.assertThrows(P2pException.class,
        () -> handler.processMessage(peer, msg));
    Assert.assertEquals(P2pException.TypeEnum.BAD_MESSAGE, tooMany.getType());
    Assert.assertEquals("big blockIds size: " + size, tooMany.getMessage());

    blockIds.clear();
    size = NetConstants.SYNC_FETCH_BATCH_NUM / 100;
    for (int i = 0; i < size; i++) {
      blockIds.add(new BlockId());
    }
    msg = new ChainInventoryMessage(blockIds, 100L);

    P2pException invalidRemain = Assert.assertThrows(P2pException.class,
        () -> handler.processMessage(peer, msg));
    Assert.assertEquals(P2pException.TypeEnum.BAD_MESSAGE, invalidRemain.getType());
    Assert.assertEquals("remain: 100, blockIds size: " + size, invalidRemain.getMessage());
    Assert.assertNotNull(msg.toString());
    Assert.assertNull(msg.getAnswerMessage());
  }

}
