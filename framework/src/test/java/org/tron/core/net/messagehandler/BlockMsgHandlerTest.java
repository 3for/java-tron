package org.tron.core.net.messagehandler;

import static org.junit.Assert.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;

import com.google.common.collect.ImmutableList;
import com.google.protobuf.ByteString;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.net.InetSocketAddress;
import java.util.ArrayList;
import java.util.List;
import javax.annotation.Resource;
import org.junit.Assert;
import org.junit.Before;
import org.junit.BeforeClass;
import org.junit.Test;
import org.mockito.Mockito;
import org.tron.common.BaseTest;
import org.tron.common.TestConstants;
import org.tron.common.utils.ByteArray;
import org.tron.common.utils.Sha256Hash;
import org.tron.core.Constant;
import org.tron.core.capsule.BlockCapsule;
import org.tron.core.capsule.BlockCapsule.BlockId;
import org.tron.core.config.Parameter;
import org.tron.core.config.args.Args;
import org.tron.core.exception.P2pException;
import org.tron.core.net.TronNetDelegate;
import org.tron.core.net.message.adv.BlockMessage;
import org.tron.core.net.peer.Item;
import org.tron.core.net.peer.PeerConnection;
import org.tron.p2p.connection.Channel;
import org.tron.protos.Protocol.Inventory.InventoryType;
import org.tron.protos.Protocol.Transaction;

public class BlockMsgHandlerTest extends BaseTest {

  @Resource
  private BlockMsgHandler handler;
  @Resource
  private PeerConnection peer;

  /**
   * init context.
   */
  @BeforeClass
  public static void init() {
    Args.setParam(new String[] {"--output-directory", dbPath(), "--debug"},
        TestConstants.TEST_CONF);
  }

  @Before
  public void before() throws Exception {
    Channel c1 = new Channel();
    InetSocketAddress a1 = new InetSocketAddress("100.1.1.1", 100);
    Field field = c1.getClass().getDeclaredField("inetAddress");
    field.setAccessible(true);
    field.set(c1, a1.getAddress());
    peer.setChannel(c1);
  }

  @Test
  public void testProcessMessage() throws P2pException {
    BlockCapsule unrequestedBlock = new BlockCapsule(1, Sha256Hash.ZERO_HASH,
        System.currentTimeMillis(), Sha256Hash.ZERO_HASH.getByteString());
    BlockMessage unrequestedMessage = new BlockMessage(unrequestedBlock);
    P2pException noRequest = Assert.assertThrows(P2pException.class,
        () -> handler.processMessage(peer, unrequestedMessage));
    assertEquals(P2pException.TypeEnum.BAD_MESSAGE, noRequest.getType());
    assertEquals("no request", noRequest.getMessage());

    List<Transaction> transactionList = ImmutableList.of(
        Transaction.newBuilder()
            .setRawData(Transaction.raw.newBuilder()
                .setData(
                    ByteString.copyFrom(
                        new byte[Parameter.ChainConstant.BLOCK_SIZE + Constant.ONE_THOUSAND])))
            .build());
    BlockCapsule oversizedBlock = new BlockCapsule(1, Sha256Hash.ZERO_HASH.getByteString(),
        System.currentTimeMillis() + 10000, transactionList);
    BlockMessage oversizedMessage = new BlockMessage(oversizedBlock);
    peer.getAdvInvRequest()
        .put(new Item(oversizedMessage.getBlockId(), InventoryType.BLOCK),
            System.currentTimeMillis());
    P2pException oversized = Assert.assertThrows(P2pException.class,
        () -> handler.processMessage(peer, oversizedMessage));
    assertEquals(P2pException.TypeEnum.BAD_MESSAGE, oversized.getType());
    assertEquals("block size over limit", oversized.getMessage());

    BlockCapsule futureBlock = new BlockCapsule(1, Sha256Hash.ZERO_HASH,
        System.currentTimeMillis() + 10000, Sha256Hash.ZERO_HASH.getByteString());
    BlockMessage futureMessage = new BlockMessage(futureBlock);
    peer.getAdvInvRequest()
        .put(new Item(futureMessage.getBlockId(), InventoryType.BLOCK), System.currentTimeMillis());
    P2pException future = Assert.assertThrows(P2pException.class,
        () -> handler.processMessage(peer, futureMessage));
    assertEquals(P2pException.TypeEnum.BAD_MESSAGE, future.getType());
    assertEquals("block time error", future.getMessage());

    BlockCapsule syncBlock = new BlockCapsule(1, Sha256Hash.ZERO_HASH,
        System.currentTimeMillis() + 1000, Sha256Hash.ZERO_HASH.getByteString());
    BlockMessage syncMessage = new BlockMessage(syncBlock);
    peer.getSyncBlockRequested().put(syncMessage.getBlockId(), System.currentTimeMillis());
    handler.processMessage(peer, syncMessage);

    BlockCapsule requestedBlock = new BlockCapsule(1, Sha256Hash.ZERO_HASH,
        System.currentTimeMillis() + 1000, Sha256Hash.ZERO_HASH.getByteString());
    BlockMessage requestedMessage = new BlockMessage(requestedBlock);
    peer.getAdvInvRequest()
        .put(new Item(requestedMessage.getBlockId(), InventoryType.BLOCK),
            System.currentTimeMillis());
    handler.processMessage(peer, requestedMessage);
  }

  @Test
  public void testProcessBlock() {
    TronNetDelegate tronNetDelegate = Mockito.mock(TronNetDelegate.class);

    try {
      Field field = handler.getClass().getDeclaredField("tronNetDelegate");
      field.setAccessible(true);
      field.set(handler, tronNetDelegate);

      BlockCapsule blockCapsule0 = new BlockCapsule(1,
          Sha256Hash.wrap(ByteString
              .copyFrom(ByteArray
                  .fromHexString(
                      "9938a342238077182498b464ac0292229938a342238077182498b464ac029222"))),
          1234,
          ByteString.copyFrom("1234567".getBytes()));

      peer.getAdvInvReceive()
          .put(new Item(blockCapsule0.getBlockId(), InventoryType.BLOCK),
              System.currentTimeMillis());

      Mockito.doReturn(true).when(tronNetDelegate).validBlock(any(BlockCapsule.class));
      Mockito.doReturn(true).when(tronNetDelegate).containBlock(any(BlockId.class));
      Mockito.doReturn(blockCapsule0.getBlockId()).when(tronNetDelegate).getHeadBlockId();
      Mockito.doNothing().when(tronNetDelegate).processBlock(any(BlockCapsule.class), anyBoolean());
      List<PeerConnection> peers = new ArrayList<>();
      peers.add(peer);
      Mockito.doReturn(peers).when(tronNetDelegate).getActivePeer();

      Method method = handler.getClass()
          .getDeclaredMethod("processBlock", PeerConnection.class, BlockCapsule.class);
      method.setAccessible(true);
      method.invoke(handler, peer, blockCapsule0);
    } catch (Exception e) {
      Assert.fail();
    }
  }
}
