package org.tron.core.db;

import com.google.common.collect.Lists;
import com.google.protobuf.ByteString;
import java.lang.ref.Reference;
import java.lang.ref.WeakReference;
import java.util.LinkedList;
import javax.annotation.Resource;
import lombok.extern.slf4j.Slf4j;
import org.junit.Assert;
import org.junit.Test;
import org.tron.common.BaseTest;
import org.tron.common.TestConstants;
import org.tron.common.utils.ByteArray;
import org.tron.common.utils.Pair;
import org.tron.common.utils.Sha256Hash;
import org.tron.core.capsule.BlockCapsule;
import org.tron.core.config.args.Args;
import org.tron.core.exception.BadNumberBlockException;
import org.tron.core.exception.NonCommonBlockException;
import org.tron.core.exception.UnLinkedBlockException;
import org.tron.protos.Protocol.Block;
import org.tron.protos.Protocol.BlockHeader;
import org.tron.protos.Protocol.BlockHeader.raw;

@Slf4j
public class KhaosDatabaseTest extends BaseTest {

  @Resource
  private KhaosDatabase khaosDatabase;

  static {
    Args.setParam(new String[]{"--output-directory", dbPath()}, TestConstants.TEST_CONF);
  }


  @Test
  public void testStartBlock() {
    BlockCapsule blockCapsule = new BlockCapsule(Block.newBuilder().setBlockHeader(
        BlockHeader.newBuilder().setRawData(raw.newBuilder().setParentHash(ByteString.copyFrom(
            ByteArray.fromHexString(
                "0304f784e4e7bae517bcab94c3e0c9214fb4ac7ff9d7d5a937d1f40031f87b81"))))).build());
    khaosDatabase.start(blockCapsule);

    Assert.assertEquals(blockCapsule, khaosDatabase.getBlock(blockCapsule.getBlockId()));
  }

  @Test
  public void testPushGetBlock() {
    BlockCapsule blockCapsule = new BlockCapsule(Block.newBuilder().setBlockHeader(
        BlockHeader.newBuilder().setRawData(raw.newBuilder().setParentHash(ByteString.copyFrom(
            ByteArray.fromHexString(
                "0304f784e4e7bae517bcab94c3e0c9214fb4ac7ff9d7d5a937d1f40031f87b81"))))).build());
    BlockCapsule blockCapsule2 = new BlockCapsule(Block.newBuilder().setBlockHeader(
        BlockHeader.newBuilder().setRawData(raw.newBuilder().setParentHash(ByteString.copyFrom(
            ByteArray.fromHexString(
                "9938a342238077182498b464ac029222ae169360e540d1fd6aee7c2ae9575a06"))))).build());
    khaosDatabase.start(blockCapsule);
    Assert.assertThrows(UnLinkedBlockException.class,
        () -> khaosDatabase.push(blockCapsule2));

    Assert.assertEquals(blockCapsule2, khaosDatabase.getBlock(blockCapsule2.getBlockId()));
    Assert.assertTrue("contain is error", khaosDatabase.containBlock(blockCapsule2.getBlockId()));

    khaosDatabase.removeBlk(blockCapsule2.getBlockId());

    Assert.assertNull("removeBlk is error", khaosDatabase.getBlock(blockCapsule2.getBlockId()));
  }


  @Test
  public void checkWeakReference() throws UnLinkedBlockException, BadNumberBlockException {
    BlockCapsule blockCapsule = new BlockCapsule(Block.newBuilder().setBlockHeader(
        BlockHeader.newBuilder().setRawData(raw.newBuilder().setParentHash(ByteString.copyFrom(
            ByteArray
                .fromHexString("0304f784e4e7bae517bcab94c3e0c9214fb4ac7ff9d7d5a937d1f40031f87b82")))
            .setNumber(0))).build());
    BlockCapsule blockCapsule2 = new BlockCapsule(Block.newBuilder().setBlockHeader(
        BlockHeader.newBuilder().setRawData(raw.newBuilder()
            .setParentHash(ByteString.copyFrom(blockCapsule.getBlockId().getBytes())).setNumber(1)))
        .build());
    Assert.assertEquals(blockCapsule.getBlockId(), blockCapsule2.getParentHash());

    khaosDatabase.start(blockCapsule);
    khaosDatabase.push(blockCapsule2);

    khaosDatabase.removeBlk(blockCapsule.getBlockId());
    logger.info("*** " + khaosDatabase.getBlock(blockCapsule.getBlockId()));
    Object object = new Object();
    Reference<Object> objectReference = new WeakReference<>(object);
    blockCapsule = null;
    object = null;
    System.gc();
    logger.info("***** object ref:" + objectReference.get());
    Assert.assertNull(objectReference.get());
    Assert.assertNull(khaosDatabase.getParentBlock(blockCapsule2.getBlockId()));
  }

  @Test
  public void testGetBranch()
      throws UnLinkedBlockException, BadNumberBlockException, NonCommonBlockException {
    final String mockedHash = "0304f784e4e7bae517bcab94c3e0c9214fb4ac7ff9d7d5a937d1f40031f87b82";
    // common parent block
    BlockCapsule parentBlock = new BlockCapsule(Block.newBuilder().setBlockHeader(
        BlockHeader.newBuilder().setRawData(raw.newBuilder().setParentHash(ByteString.copyFrom(
            ByteArray.fromHexString(mockedHash)))
            .setNumber(0))).build());
    // fork-chain-A
    // longer than chainB, share the common parent block with fork-chain-B
    BlockCapsule block1OnforkA = new BlockCapsule(
        1, parentBlock.getBlockId(), 0, ByteString.EMPTY);
    BlockCapsule block2OnforkA = new BlockCapsule(
        2, block1OnforkA.getBlockId(), 0, ByteString.EMPTY);
    LinkedList<KhaosDatabase.KhaosBlock> forkA = Lists.newLinkedList();
    forkA.add(new KhaosDatabase.KhaosBlock(block2OnforkA));
    forkA.add(new KhaosDatabase.KhaosBlock(block1OnforkA));
    // fork-chain-B
    BlockCapsule block1OnforkB = new BlockCapsule(
        1, parentBlock.getBlockId(), 1, ByteString.EMPTY);
    LinkedList<KhaosDatabase.KhaosBlock> forkB = Lists.newLinkedList();
    forkB.add(new KhaosDatabase.KhaosBlock(block1OnforkB));

    khaosDatabase.start(parentBlock);
    khaosDatabase.push(block1OnforkA);
    khaosDatabase.push(block2OnforkA);
    khaosDatabase.push(block1OnforkB);
    // Keep the static type as Sha256Hash so this exercises the strict branch lookup overload.
    Sha256Hash forkAHead = block2OnforkA.getBlockId();
    Sha256Hash forkBHead = block1OnforkB.getBlockId();
    // case: block num of param1 > block num of param2
    Pair<LinkedList<KhaosDatabase.KhaosBlock>, LinkedList<KhaosDatabase.KhaosBlock>> result1 =
        khaosDatabase.getBranch(forkAHead, forkBHead);
    Assert.assertEquals(forkA, result1.getKey());
    Assert.assertEquals(forkB, result1.getValue());
    // case: block num of param2 > block num of param1
    Pair<LinkedList<KhaosDatabase.KhaosBlock>, LinkedList<KhaosDatabase.KhaosBlock>> result2 =
        khaosDatabase.getBranch(forkBHead, forkAHead);
    Assert.assertEquals(forkB, result2.getKey());
    Assert.assertEquals(forkA, result2.getValue());
  }

  @Test(expected = UnsupportedOperationException.class)
  public void testIsNotEmpty() {
    BlockCapsule blockCapsule = new BlockCapsule(Block.newBuilder().setBlockHeader(
        BlockHeader.newBuilder().setRawData(raw.newBuilder().setParentHash(ByteString.copyFrom(
            ByteArray.fromHexString(
                "0304f784e4e7bae517bcab94c3e0c9214fb4ac7ff9d7d5a937d1f40031f87b81"))))).build());
    khaosDatabase.start(blockCapsule);
    khaosDatabase.isNotEmpty();
  }
}
