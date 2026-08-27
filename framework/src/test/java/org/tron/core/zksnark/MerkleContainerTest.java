package org.tron.core.zksnark;

import com.google.protobuf.Any;
import com.google.protobuf.ByteString;
import javax.annotation.Resource;
import org.junit.AfterClass;
import org.junit.Assert;
import org.junit.BeforeClass;
import org.junit.Test;
import org.tron.common.BaseTest;
import org.tron.common.TestConstants;
import org.tron.common.parameter.CommonParameter;
import org.tron.common.utils.ByteArray;
import org.tron.common.utils.Sha256Hash;
import org.tron.common.zksnark.IncrementalMerkleVoucherContainer;
import org.tron.core.Wallet;
import org.tron.core.capsule.BlockCapsule;
import org.tron.core.capsule.BlockCapsule.BlockId;
import org.tron.core.capsule.IncrementalMerkleTreeCapsule;
import org.tron.core.capsule.IncrementalMerkleVoucherCapsule;
import org.tron.core.capsule.PedersenHashCapsule;
import org.tron.core.capsule.TransactionCapsule;
import org.tron.core.config.args.Args;
import org.tron.core.exception.ZksnarkException;
import org.tron.protos.Protocol.Block;
import org.tron.protos.Protocol.Transaction;
import org.tron.protos.Protocol.Transaction.Contract.ContractType;
import org.tron.protos.contract.ShieldContract.IncrementalMerkleTree;
import org.tron.protos.contract.ShieldContract.IncrementalMerkleVoucherInfo;
import org.tron.protos.contract.ShieldContract.OutputPoint;
import org.tron.protos.contract.ShieldContract.OutputPointInfo;
import org.tron.protos.contract.ShieldContract.PedersenHash;
import org.tron.protos.contract.ShieldContract.ReceiveDescription;
import org.tron.protos.contract.ShieldContract.ShieldedTransferContract;

public class MerkleContainerTest extends BaseTest {

  @Resource
  private Wallet wallet;


  private static boolean origShieldedApi;

  static {
    Args.setParam(new String[]{"-d", dbPath()}, TestConstants.TEST_CONF);
  }

  @BeforeClass
  public static void enableShieldedApi() {
    origShieldedApi = Args.getInstance().allowShieldedTransactionApi;
    Args.getInstance().allowShieldedTransactionApi = true;
  }

  @AfterClass
  public static void restoreShieldedApi() {
    Args.getInstance().allowShieldedTransactionApi = origShieldedApi;
  }

  private Transaction createTransaction(String strCm1, String strCm2) {
    ByteString cm1 = ByteString.copyFrom(ByteArray.fromHexString(strCm1));
    ByteString cm2 = ByteString.copyFrom(ByteArray.fromHexString(strCm2));
    ReceiveDescription receiveDescription1 = ReceiveDescription.newBuilder().setNoteCommitment(cm1)
        .build();
    ReceiveDescription receiveDescription2 = ReceiveDescription.newBuilder().setNoteCommitment(cm2)
        .build();
    ShieldedTransferContract contract = ShieldedTransferContract.newBuilder()
        .addReceiveDescription(receiveDescription1)
        .addReceiveDescription(receiveDescription2).build();
    Transaction.raw.Builder transactionBuilder = Transaction.raw.newBuilder().addContract(
        Transaction.Contract.newBuilder().setType(ContractType.ShieldedTransferContract)
            .setParameter(
                Any.pack(contract)).build());
    return Transaction.newBuilder().setRawData(transactionBuilder.build())
        .build();
  }

  private void initMerkleTreeWitnessInfo() throws ZksnarkException {
    {
      IncrementalMerkleTreeCapsule tree = new IncrementalMerkleTreeCapsule();

      {
        long blockNum = 99;
        String s1 = "556f3af94225d46b1ef652abc9005dee873b2e245eef07fd5be587e0f21023b0";
        PedersenHashCapsule compressCapsule1 = new PedersenHashCapsule();
        compressCapsule1.setContent(ByteString.copyFrom(ByteArray.fromHexString(s1)));
        PedersenHash a = compressCapsule1.getInstance();
        tree.toMerkleTreeContainer().append(a);
        dbManager.getMerkleTreeStore().put(tree.toMerkleTreeContainer().getMerkleTreeKey(), tree);
        dbManager.getChainBaseManager().getMerkleTreeIndexStore()
            .put(blockNum, tree.toMerkleTreeContainer().getMerkleTreeKey());
      }

      //two transaction,the first transaction is the currentTransaction
      {
        long blockNum = 100L;
        String cm1 = "5814b127a6c6b8f07ed03f0f6e2843ff04c9851ff824a4e5b4dad5b5f3475722";
        String cm2 = "6c030e6d7460f91668cc842ceb78cdb54470469e78cd59cf903d3a6e1aa03e7c";
        Transaction transaction = createTransaction(cm1, cm2);
        String cm3 = "30a0d08406b9e3693ee4c062bd1e6816f95bf14f5a13aafa1d57942c6c1d4250";
        String cm4 = "12fc3e7298eb327a88abcc406fbe595e45dddd9b4209803b2e0baa3a8663ecaa";
        Transaction transaction2 = createTransaction(cm3, cm4);
        Block block = Block.newBuilder().addTransactions(0, transaction)
            .addTransactions(1, transaction2).build();
        Sha256Hash blockKey = Sha256Hash.of(CommonParameter
            .getInstance().isECKeyCryptoEngine(), ByteArray.fromLong(blockNum));
        BlockId blockId = new BlockId(blockKey, blockNum);
        dbManager.getBlockStore().put(blockId.getBytes(), new BlockCapsule(block));
        dbManager.getBlockIndexStore().put(blockId);

        TransactionCapsule transactionCapsule1 = new TransactionCapsule(transaction);
        transactionCapsule1.setBlockNum(blockNum);
        dbManager.getTransactionStore()
            .put(transactionCapsule1.getTransactionId().getBytes(),
                transactionCapsule1);

        PedersenHashCapsule compressCapsule1 = new PedersenHashCapsule();
        compressCapsule1.setContent(ByteString.copyFrom(ByteArray.fromHexString(cm1)));
        PedersenHash a = compressCapsule1.getInstance();
        tree.toMerkleTreeContainer().append(a);
        PedersenHashCapsule compressCapsule2 = new PedersenHashCapsule();
        compressCapsule2.setContent(ByteString.copyFrom(ByteArray.fromHexString(cm2)));
        PedersenHash b = compressCapsule2.getInstance();
        tree.toMerkleTreeContainer().append(b);
        PedersenHashCapsule compressCapsule3 = new PedersenHashCapsule();
        compressCapsule3.setContent(ByteString.copyFrom(ByteArray.fromHexString(cm3)));
        PedersenHash c = compressCapsule3.getInstance();
        tree.toMerkleTreeContainer().append(c);
        PedersenHashCapsule compressCapsule4 = new PedersenHashCapsule();
        compressCapsule4.setContent(ByteString.copyFrom(ByteArray.fromHexString(cm4)));

        PedersenHash d = compressCapsule4.getInstance();
        tree.toMerkleTreeContainer().append(d);
        dbManager.getMerkleTreeStore().put(tree.toMerkleTreeContainer().getMerkleTreeKey(), tree);
      }
      {
        long blockNum = 101;
        String cm1 = "021a35cfe13d16891c1409d0f6e8865f51dd54792e5108a6f9e55e0dd44867f7";
        String cm2 = "2e0bfc1e123edcb6252251611650f3667371f781b60302385c414716c75e8abc";
        Transaction transaction = createTransaction(cm1, cm2);
        Block block = Block.newBuilder().addTransactions(0, transaction).build();
        Sha256Hash blockKey = Sha256Hash.of(CommonParameter
            .getInstance().isECKeyCryptoEngine(), ByteArray.fromLong(blockNum));
        BlockId blockId = new BlockId(blockKey, blockNum);
        dbManager.getBlockStore().put(blockId.getBytes(), new BlockCapsule(block));
        dbManager.getBlockIndexStore().put(blockId);

        PedersenHashCapsule compressCapsule1 = new PedersenHashCapsule();
        compressCapsule1.setContent(ByteString.copyFrom(ByteArray.fromHexString(cm1)));
        PedersenHash a = compressCapsule1.getInstance();
        tree.toMerkleTreeContainer().append(a);
        PedersenHashCapsule compressCapsule2 = new PedersenHashCapsule();
        compressCapsule2.setContent(ByteString.copyFrom(ByteArray.fromHexString(cm2)));
        PedersenHash b = compressCapsule2.getInstance();
        tree.toMerkleTreeContainer().append(b);
        dbManager.getMerkleTreeStore().put(tree.toMerkleTreeContainer().getMerkleTreeKey(), tree);

        dbManager.getChainBaseManager().getMerkleTreeIndexStore()
            .put(blockNum, tree.toMerkleTreeContainer().getMerkleTreeKey());
      }
      //two transaction,the second transaction is the currentTransaction
      {
        long blockNum = 102L;
        String cm1 = "11a5e54bf9a9b57e1c163904999ad1527f1e126c685111e18193decca2dd1ada";
        String cm2 = "4674f7836089063143fc18b673b2d92f888c63380e3680385d47bcdbd5fe273a";
        Transaction transaction = createTransaction(cm1, cm2);
        String cm3 = "0830165f36a69e416d51cc09cc5668692dee35d98539d3317999fdf87d8fcac7";
        String cm4 = "02372c746664e0898576972ca6d0500c7c8ec42f144622349d133b06e837faf0";
        Transaction transaction2 = createTransaction(cm3, cm4);
        Block block = Block.newBuilder().addTransactions(0, transaction)
            .addTransactions(1, transaction2).build();
        Sha256Hash blockKey = Sha256Hash.of(CommonParameter
            .getInstance().isECKeyCryptoEngine(), ByteArray.fromLong(blockNum));
        BlockId blockId = new BlockId(blockKey, blockNum);
        dbManager.getBlockStore().put(blockId.getBytes(), new BlockCapsule(block));
        dbManager.getBlockIndexStore().put(blockId);

        TransactionCapsule transactionCapsule = new TransactionCapsule(transaction2);
        transactionCapsule.setBlockNum(blockNum);

        dbManager.getTransactionStore()
            .put(transactionCapsule.getTransactionId().getBytes(),
                transactionCapsule);

        PedersenHashCapsule compressCapsule1 = new PedersenHashCapsule();
        compressCapsule1.setContent(ByteString.copyFrom(ByteArray.fromHexString(cm1)));
        PedersenHash a = compressCapsule1.getInstance();
        tree.toMerkleTreeContainer().append(a);
        PedersenHashCapsule compressCapsule2 = new PedersenHashCapsule();
        compressCapsule2.setContent(ByteString.copyFrom(ByteArray.fromHexString(cm2)));
        PedersenHash b = compressCapsule2.getInstance();
        tree.toMerkleTreeContainer().append(b);
        dbManager.getMerkleTreeStore().put(tree.toMerkleTreeContainer().getMerkleTreeKey(), tree);
        PedersenHashCapsule compressCapsule3 = new PedersenHashCapsule();
        compressCapsule3.setContent(ByteString.copyFrom(ByteArray.fromHexString(cm3)));
        PedersenHash c = compressCapsule3.getInstance();
        tree.toMerkleTreeContainer().append(c);
        PedersenHashCapsule compressCapsule4 = new PedersenHashCapsule();
        compressCapsule4.setContent(ByteString.copyFrom(ByteArray.fromHexString(cm4)));
        PedersenHash d = compressCapsule4.getInstance();
        tree.toMerkleTreeContainer().append(d);
        dbManager.getMerkleTreeStore().put(tree.toMerkleTreeContainer().getMerkleTreeKey(), tree);
      }
      {
        long blockNum = 103L;
        String cm1 = "08c6d7dd3d2e387f7b84d6769f2b6cbe308918ab81e0f7321bd0945868d7d4e6";
        String cm2 = "26e8c4061f2ad984d19f2c0a4436b9800e529069c0b0d3186d4683e83bb7eb8c";
        Transaction transaction = createTransaction(cm1, cm2);
        Block block = Block.newBuilder().addTransactions(0, transaction).build();
        Sha256Hash blockKey = Sha256Hash.of(CommonParameter
            .getInstance().isECKeyCryptoEngine(), ByteArray.fromLong(blockNum));
        BlockId blockId = new BlockId(blockKey, blockNum);
        dbManager.getBlockStore().put(blockId.getBytes(), new BlockCapsule(block));
        dbManager.getBlockIndexStore().put(blockId);

        PedersenHashCapsule compressCapsule1 = new PedersenHashCapsule();
        compressCapsule1.setContent(ByteString.copyFrom(ByteArray.fromHexString(cm1)));
        PedersenHash a = compressCapsule1.getInstance();
        tree.toMerkleTreeContainer().append(a);
        PedersenHashCapsule compressCapsule2 = new PedersenHashCapsule();
        compressCapsule2.setContent(ByteString.copyFrom(ByteArray.fromHexString(cm2)));
        PedersenHash b = compressCapsule2.getInstance();
        tree.toMerkleTreeContainer().append(b);
        dbManager.getMerkleTreeStore().put(tree.toMerkleTreeContainer().getMerkleTreeKey(), tree);
      }
    }
  }

  @Test
  public void getMerkleTreeWitnessInfoTest() throws Exception {
    //init
    initMerkleTreeWitnessInfo();

    //blockNum:100,txNum:1
    ByteString txId1 = ByteString.copyFrom(ByteArray
        .fromHexString("59051fde6f2e47306f17fca57a4aab3c12d948b7980fd4163c93520b69a7b982"));
    OutputPoint outputPoint1 = OutputPoint.newBuilder().setHash(txId1).setIndex(0).build();
    //blockNum:103,txNum:2
    ByteString txId2 = ByteString.copyFrom(ByteArray
        .fromHexString("7f8726373dcddf40409ace76b904369848f0a6d89ba5db851ed9515a80b52f34"));
    OutputPoint outputPoint2 = OutputPoint.newBuilder().setHash(txId2).setIndex(0).build();
    int number = 0;
    OutputPointInfo outputPointInfo = OutputPointInfo.newBuilder().addOutPoints(outputPoint1)
        .addOutPoints(outputPoint2).setBlockNum(number).build();
    IncrementalMerkleVoucherInfo merkleTreeWitnessInfo = wallet
        .getMerkleTreeVoucherInfo(outputPointInfo);

    Assert.assertEquals(2, merkleTreeWitnessInfo.getVouchersCount());
    Assert.assertEquals(2, merkleTreeWitnessInfo.getPathsCount());

    IncrementalMerkleVoucherCapsule capsule1 = new IncrementalMerkleVoucherCapsule(
        merkleTreeWitnessInfo.getVouchers(0));
    IncrementalMerkleVoucherCapsule capsule2 = new IncrementalMerkleVoucherCapsule(
        merkleTreeWitnessInfo.getVouchers(1));
    Assert.assertTrue(capsule1.toMerkleVoucherContainer().size() > 0);
    Assert.assertTrue(capsule2.toMerkleVoucherContainer().size() > 0);
    Assert.assertEquals(
        ByteString.copyFrom(capsule1.toMerkleVoucherContainer().path().encode()),
        merkleTreeWitnessInfo.getPaths(0));
    Assert.assertEquals(
        ByteString.copyFrom(capsule2.toMerkleVoucherContainer().path().encode()),
        merkleTreeWitnessInfo.getPaths(1));
    Assert.assertEquals(merkleTreeWitnessInfo.getVouchers(0).getRt(),
        merkleTreeWitnessInfo.getVouchers(1).getRt());

  }

  @Test
  public void append() throws ZksnarkException {
    IncrementalMerkleTreeCapsule tree = new IncrementalMerkleTreeCapsule();
    int b = 255;

    for (int a = 1; a < b; a++) {
      int i = 1;
      for (; i <= a; i++) {
        byte[] bytes = new byte[32];
        bytes[0] = (byte) i;
        PedersenHash c = PedersenHash.newBuilder().setContent(ByteString.copyFrom(bytes)).build();
        tree.toMerkleTreeContainer().append(c);
      }
      IncrementalMerkleVoucherContainer witnessa = tree.toMerkleTreeContainer().toVoucher();
      for (int j = i; j <= b; j++) {
        byte[] bytes = new byte[32];
        bytes[0] = (byte) j;
        PedersenHash c = PedersenHash.newBuilder().setContent(ByteString.copyFrom(bytes)).build();
        witnessa.append(c);
      }

      for (int j = i; j <= b; j++) {
        byte[] bytes = new byte[32];
        bytes[0] = (byte) j;
        PedersenHash c = PedersenHash.newBuilder().setContent(ByteString.copyFrom(bytes)).build();
        tree.toMerkleTreeContainer().append(c);
      }
      IncrementalMerkleVoucherContainer witnessb = tree.toMerkleTreeContainer().toVoucher();

      byte[] roota = witnessa.root().getContent().toByteArray();
      byte[] rootb = witnessb.root().getContent().toByteArray();

      Assert.assertArrayEquals(roota, rootb);
    }
  }

}
