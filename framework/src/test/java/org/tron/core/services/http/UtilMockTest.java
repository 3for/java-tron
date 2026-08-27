package org.tron.core.services.http;

import com.google.protobuf.ByteString;
import com.google.protobuf.Descriptors;
import java.security.InvalidParameterException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.junit.Assert;
import org.junit.Test;
import org.tron.api.GrpcAPI;
import org.tron.common.utils.Sha256Hash;
import org.tron.core.capsule.BlockCapsule;
import org.tron.core.capsule.TransactionCapsule;
import org.tron.json.JSONArray;
import org.tron.json.JSONObject;
import org.tron.p2p.utils.ByteArray;
import org.tron.protos.Protocol;
import org.tron.protos.contract.BalanceContract;
import org.tron.protos.contract.SmartContractOuterClass;

public class UtilMockTest {
  @Test
  public void testPrintTransactionFee() {
    Protocol.ResourceReceipt resourceReceipt = Protocol.ResourceReceipt.newBuilder()
        .setEnergyUsage(7L)
        .build();
    Protocol.TransactionInfo result  = Protocol.TransactionInfo.newBuilder()
        .setReceipt(resourceReceipt)
        .build();
    String transactionFee = JsonFormat.printToString(result, true);
    String out = Util.printTransactionFee(transactionFee);
    JSONObject json = JSONObject.parseObject(out);
    Assert.assertTrue(json.containsKey("Receipt"));
    Assert.assertEquals(7L,
        ((Number) json.getJSONObject("Receipt").get("energy_usage")).longValue());
  }

  @Test
  public void testPrintBlockList() {
    BlockCapsule blockCapsule1 = new BlockCapsule(1, Sha256Hash.ZERO_HASH,
        System.currentTimeMillis(), Sha256Hash.ZERO_HASH.getByteString());
    BlockCapsule blockCapsule2 = new BlockCapsule(2, Sha256Hash.ZERO_HASH,
        System.currentTimeMillis(), Sha256Hash.ZERO_HASH.getByteString());
    GrpcAPI.BlockList list = GrpcAPI.BlockList.newBuilder()
        .addBlock(blockCapsule1.getInstance())
        .addBlock(blockCapsule2.getInstance())
        .build();
    String out = Util.printBlockList(list, true);
    Assert.assertNotNull(out);

    JSONObject json = JSONObject.parseObject(out);
    Assert.assertTrue(json.containsKey("block"));
    JSONArray blockArray = json.getJSONArray("block");
    Assert.assertEquals(2, blockArray.size());

    // verify each block has correct structure
    for (int i = 0; i < blockArray.size(); i++) {
      JSONObject blockJson = blockArray.getJSONObject(i);
      Assert.assertTrue(blockJson.containsKey("blockID"));
      Assert.assertTrue(blockJson.containsKey("block_header"));
      Assert.assertFalse(blockJson.getString("blockID").isEmpty());
      JSONObject blockHeader = blockJson.getJSONObject("block_header");
      Assert.assertNotNull(blockHeader);
      Assert.assertTrue(blockHeader.containsKey("raw_data"));
    }
  }

  @Test
  public void testPrintBlockToJSONEmptyTransactions() {
    BlockCapsule blockCapsule = new BlockCapsule(1, Sha256Hash.ZERO_HASH,
        System.currentTimeMillis(), Sha256Hash.ZERO_HASH.getByteString());
    JSONObject json = Util.printBlockToJSON(blockCapsule.getInstance(), true);
    Assert.assertTrue(json.containsKey("blockID"));
    Assert.assertTrue(json.containsKey("block_header"));
    Assert.assertFalse(json.containsKey("transactions"));
    Assert.assertFalse(json.getString("blockID").isEmpty());
    JSONObject blockHeader = json.getJSONObject("block_header");
    Assert.assertNotNull(blockHeader);
    Assert.assertTrue(blockHeader.containsKey("raw_data"));
  }

  @Test
  public void testPrintBlockToJSONWithTransactions() {
    // Structural invariants must hold under either visible flag; the flag-driven
    // encoding difference is covered by testPrintBlockToJSONVisibleFlagAffectsAddressEncoding.
    for (boolean visible : new boolean[]{true, false}) {
      BlockCapsule blockCapsule = new BlockCapsule(1, Sha256Hash.ZERO_HASH,
          System.currentTimeMillis(), Sha256Hash.ZERO_HASH.getByteString());
      blockCapsule.addTransaction(getTransactionCapsuleExample());

      JSONObject json = Util.printBlockToJSON(blockCapsule.getInstance(), visible);

      String msg = "visible=" + visible;
      Assert.assertTrue(msg, json.containsKey("blockID"));
      Assert.assertTrue(msg, json.containsKey("block_header"));
      Assert.assertTrue(msg, json.containsKey("transactions"));
      Assert.assertFalse(msg, json.getString("blockID").isEmpty());
      JSONObject blockHeader = json.getJSONObject("block_header");
      Assert.assertNotNull(msg, blockHeader);
      Assert.assertTrue(msg, blockHeader.containsKey("raw_data"));

      JSONArray txArray = json.getJSONArray("transactions");
      Assert.assertEquals(msg, 1, txArray.size());
      JSONObject txJson = txArray.getJSONObject(0);
      Assert.assertTrue(msg, txJson.containsKey("txID"));
      Assert.assertTrue(msg, txJson.containsKey("raw_data"));
    }
  }

  @Test
  public void testPrintBlockToJSONVisibleFlagAffectsAddressEncoding() {
    // Pins the optimized printBlockToJSON against the prior behavior: the
    // visible flag must still thread through to JsonFormat so address-bearing
    // fields switch encoding while byte-identity fields stay stable.
    ByteString witnessAddress = ByteString.copyFrom(
        ByteArray.fromHexString("41548794500882809695a8a687866e76d4271a1abc"));
    BlockCapsule blockCapsule = new BlockCapsule(1, Sha256Hash.ZERO_HASH,
        System.currentTimeMillis(), witnessAddress);

    JSONObject visible = Util.printBlockToJSON(blockCapsule.getInstance(), true);
    JSONObject hidden = Util.printBlockToJSON(blockCapsule.getInstance(), false);

    // blockID is derived from raw bytes; identical under either flag.
    Assert.assertEquals(visible.getString("blockID"), hidden.getString("blockID"));

    // Overall block_header must differ because witness_address is re-encoded.
    String headerVisible = visible.getJSONObject("block_header").toJSONString();
    String headerHidden = hidden.getJSONObject("block_header").toJSONString();
    Assert.assertNotEquals(headerVisible, headerHidden);

    // visible=true renders a mainnet address as Base58 starting with 'T'.
    String witnessVisible = visible.getJSONObject("block_header")
        .getJSONObject("raw_data").getString("witness_address");
    Assert.assertNotNull(witnessVisible);
    Assert.assertTrue("visible=true witness_address should be Base58 ('T...'), got: "
        + witnessVisible, witnessVisible.startsWith("T"));

    // visible=false keeps witness_address in raw (non-Base58) form.
    String witnessHidden = hidden.getJSONObject("block_header")
        .getJSONObject("raw_data").getString("witness_address");
    Assert.assertNotNull(witnessHidden);
    Assert.assertNotEquals(witnessVisible, witnessHidden);
  }

  @Test
  public void testPrintBlockToJSONTransactionsKeyMatchesLegacyImpl() {
    // Legacy impl produced JSON via JsonFormat.printToString(block, selfType),
    // which omits repeated fields when empty. New impl mirrors that with an
    // explicit isEmpty() guard. Pin parity using JsonFormat output as ground
    // truth so a future refactor can't quietly start emitting "transactions": []
    // (or stop emitting the key when non-empty).
    BlockCapsule empty = new BlockCapsule(1, Sha256Hash.ZERO_HASH,
        System.currentTimeMillis(), Sha256Hash.ZERO_HASH.getByteString());
    assertTransactionsKeyMatchesLegacy(empty.getInstance(), false);

    BlockCapsule nonEmpty = new BlockCapsule(1, Sha256Hash.ZERO_HASH,
        System.currentTimeMillis(), Sha256Hash.ZERO_HASH.getByteString());
    nonEmpty.addTransaction(getTransactionCapsuleExample());
    assertTransactionsKeyMatchesLegacy(nonEmpty.getInstance(), true);
  }

  private static void assertTransactionsKeyMatchesLegacy(Protocol.Block block,
      boolean expectTransactionsKey) {
    JSONObject legacy = JSONObject.parseObject(JsonFormat.printToString(block, true));
    Assert.assertEquals("legacy JsonFormat parity broken — proto behavior changed?",
        expectTransactionsKey, legacy.containsKey("transactions"));

    JSONObject actual = Util.printBlockToJSON(block, true);
    Assert.assertEquals("new impl diverged from legacy on 'transactions' key presence",
        expectTransactionsKey, actual.containsKey("transactions"));
  }

  @Test
  public void testPrintBlockToJSONCoversAllProtoTopLevelFields() {
    // Guards against proto field drift: the old impl delegated to JsonFormat on
    // the whole Block message, so any new top-level Block field appeared
    // automatically. The new impl hand-assembles the JSON, so a future proto
    // field would be silently dropped. Reflect over Block's descriptor and
    // assert every declared top-level field is handled.
    Map<String, String> protoFieldToJsonKey = new HashMap<>();
    protoFieldToJsonKey.put("block_header", "block_header");
    // "transactions" is present only when non-empty; parity verified in
    // testPrintBlockToJSONTransactionsKeyMatchesLegacyImpl.
    protoFieldToJsonKey.put("transactions", "transactions");

    for (Descriptors.FieldDescriptor f : Protocol.Block.getDescriptor().getFields()) {
      Assert.assertTrue(
          "Block proto field '" + f.getName() + "' is not handled by printBlockToJSON. "
              + "If you added a new top-level field, extend printBlockToJSON and this test.",
          protoFieldToJsonKey.containsKey(f.getName()));
    }
  }

  @Test
  public void testPrintTransactionList() {
    TransactionCapsule transactionCapsule = getTransactionCapsuleExample();
    GrpcAPI.TransactionList list = GrpcAPI.TransactionList.newBuilder()
        .addTransaction(transactionCapsule.getInstance())
        .build();
    String out = Util.printTransactionList(list, true);
    JSONArray transactions = JSONObject.parseObject(out).getJSONArray("transaction");
    Assert.assertEquals(1, transactions.size());
    Assert.assertTrue(transactions.getJSONObject(0).containsKey("txID"));
    Assert.assertTrue(transactions.getJSONObject(0).containsKey("raw_data"));
  }

  private TransactionCapsule getTransactionCapsuleExample() {
    final String OWNER_ADDRESS = "41548794500882809695a8a687866e76d4271a1abc";
    final String RECEIVER_ADDRESS = "41abd4b9367799eaa3197fecb144eb71de1e049150";
    BalanceContract.TransferContract.Builder builder2 =
        BalanceContract.TransferContract.newBuilder()
            .setOwnerAddress(
                ByteString.copyFrom(ByteArray.fromHexString(OWNER_ADDRESS)))
            .setToAddress(
                ByteString.copyFrom(ByteArray.fromHexString(RECEIVER_ADDRESS)));
    return new TransactionCapsule(builder2.build(),
        Protocol.Transaction.Contract.ContractType.TransferContract);
  }

  @Test
  public void testPrintTransactionSignWeight() {
    TransactionCapsule transactionCapsule = getTransactionCapsuleExample();
    GrpcAPI.TransactionExtention transactionExtention =
        GrpcAPI.TransactionExtention.newBuilder()
            .setTransaction(transactionCapsule.getInstance())
            .build();
    GrpcAPI.TransactionSignWeight txSignWeight =
        GrpcAPI.TransactionSignWeight.newBuilder()
            .setTransaction(transactionExtention)
            .build();

    String out = Util.printTransactionSignWeight(txSignWeight, true);
    JSONObject transaction = JSONObject.parseObject(out)
        .getJSONObject("transaction").getJSONObject("transaction");
    Assert.assertTrue(transaction.containsKey("txID"));
    Assert.assertTrue(transaction.containsKey("raw_data"));
  }

  @Test
  public void testPrintTransactionApprovedList() {
    TransactionCapsule transactionCapsule = getTransactionCapsuleExample();
    GrpcAPI.TransactionExtention transactionExtention =
        GrpcAPI.TransactionExtention.newBuilder()
            .setTransaction(transactionCapsule.getInstance())
            .build();
    GrpcAPI.TransactionApprovedList transactionApprovedList =
        GrpcAPI.TransactionApprovedList.newBuilder()
            .setTransaction(transactionExtention)
            .build();
    String out = Util.printTransactionApprovedList(
        transactionApprovedList, true);
    JSONObject transaction = JSONObject.parseObject(out)
        .getJSONObject("transaction").getJSONObject("transaction");
    Assert.assertTrue(transaction.containsKey("txID"));
    Assert.assertTrue(transaction.containsKey("raw_data"));
  }

  @Test
  public void testGenerateContractAddress() {
    final String OWNER_ADDRESS = "41548794500882809695a8a687866e76d4271a1abc";
    TransactionCapsule transactionCapsule = getTransactionCapsuleExample();
    byte[] out = Util.generateContractAddress(
        transactionCapsule.getInstance(), ByteArray.fromHexString(OWNER_ADDRESS));
    Assert.assertEquals(21, out.length);
    Assert.assertEquals(0x41, out[0] & 0xff);
    Assert.assertArrayEquals(out, Util.generateContractAddress(
        transactionCapsule.getInstance(), ByteArray.fromHexString(OWNER_ADDRESS)));
  }

  @Test
  public void testPrintTransactionToJSON() {
    final String OWNER_ADDRESS = "41548794500882809695a8a687866e76d4271a1abc";
    SmartContractOuterClass.CreateSmartContract.Builder builder2 =
        SmartContractOuterClass.CreateSmartContract.newBuilder()
            .setOwnerAddress(
                ByteString.copyFrom(ByteArray.fromHexString(OWNER_ADDRESS)));
    TransactionCapsule transactionCapsule = new TransactionCapsule(builder2.build(),
        Protocol.Transaction.Contract.ContractType.CreateSmartContract);

    JSONObject out = Util.printTransactionToJSON(
        transactionCapsule.getInstance(), true);
    Assert.assertTrue(out.containsKey("txID"));
    Assert.assertTrue(out.containsKey("raw_data"));
    String contractAddress = out.getString("contract_address");
    Assert.assertEquals(42, contractAddress.length());
    Assert.assertTrue(contractAddress.startsWith("41"));
  }

  @Test
  public void testGetContractType() {
    String out = Util.getContractType("{\"contractType\":\"123\"}\n");
    Assert.assertEquals("123", out);
  }

  @Test
  public void testGetHexAddress() {
    String out = Util.getHexAddress("TBxSocpujP6UGKV5ydXNVTDQz7fAgdmoaB");
    Assert.assertEquals(42, out.length());
    Assert.assertTrue(out.startsWith("41"));

    Assert.assertNull(Util.getHexAddress(null));
  }

  @Test
  public void testSetTransactionPermissionId() {
    TransactionCapsule transactionCapsule = getTransactionCapsuleExample();
    Protocol.Transaction out = Util.setTransactionPermissionId(
        123, transactionCapsule.getInstance());
    Assert.assertEquals(123, out.getRawData().getContract(0).getPermissionId());
  }

  @Test
  public void testSetTransactionExtraData() {
    TransactionCapsule transactionCapsule = getTransactionCapsuleExample();
    JSONObject jsonObject = JSONObject.parseObject("{\"extra_data\":\"test\"}");
    Protocol.Transaction out = Util.setTransactionExtraData(jsonObject,
        transactionCapsule.getInstance(), true);
    Assert.assertEquals(ByteString.copyFromUtf8("test"), out.getRawData().getData());
  }

  @Test
  public void testConvertOutput() {
    Protocol.Account account = Protocol.Account.newBuilder().build();
    String out = Util.convertOutput(account);
    Assert.assertEquals("{}", out);

    account = Protocol.Account.newBuilder()
        .setAssetIssuedID(ByteString.copyFromUtf8("asset_issued_ID"))
        .build();
    out = Util.convertOutput(account);
    Assert.assertEquals("asset_issued_ID",
        JSONObject.parseObject(out).getString("asset_issued_ID"));
  }

  @Test
  public void testConvertLogAddressToTronAddress() {
    List<Protocol.TransactionInfo.Log> logs = new ArrayList<>();
    logs.add(Protocol.TransactionInfo.Log.newBuilder()
        .setAddress(ByteString.copyFrom("address".getBytes()))
        .setData(ByteString.copyFrom("data".getBytes()))
        .addTopics(ByteString.copyFrom("topic".getBytes()))
        .build());

    Protocol.TransactionInfo.Builder builder = Protocol.TransactionInfo.newBuilder()
        .addAllLog(logs);
    List<Protocol.TransactionInfo.Log>  logList =
        Util.convertLogAddressToTronAddress(builder.build());
    Assert.assertEquals(1, logList.size());
    Protocol.TransactionInfo.Log converted = logList.get(0);
    Assert.assertEquals(ByteString.copyFromUtf8("data"), converted.getData());
    Assert.assertEquals(ByteString.copyFromUtf8("topic"), converted.getTopics(0));
    byte[] convertedAddress = converted.getAddress().toByteArray();
    Assert.assertEquals(21, convertedAddress.length);
    Assert.assertEquals(0x41, convertedAddress[0] & 0xff);
    Assert.assertArrayEquals("address".getBytes(),
        Arrays.copyOfRange(convertedAddress, convertedAddress.length - "address".length(),
            convertedAddress.length));
  }

  @Test
  public void testValidateParameter() {
    String contract = "{\"address\":\"owner_address\"}";
    InvalidParameterException missingOwner = Assert.assertThrows(
        InvalidParameterException.class,
        () -> Util.validateParameter(contract));
    Assert.assertEquals("owner_address isn't set.", missingOwner.getMessage());
    String contract1 =
        "{\"owner_address\":\"owner_address\","
            + " \"contract_address1\":\"contract_address\", \"data1\":\"data\"}";
    InvalidParameterException missingTarget = Assert.assertThrows(
        InvalidParameterException.class,
        () -> Util.validateParameter(contract1));
    Assert.assertEquals(
        "At least one of contract_address and data must be set.", missingTarget.getMessage());
    String contract2 =
        "{\"owner_address\":\"owner_address\", "
            + "\"function_selector\":\"function_selector\", \"data\":\"data\"}";
    InvalidParameterException conflictingDeployInput = Assert.assertThrows(
        InvalidParameterException.class,
        () -> Util.validateParameter(contract2));
    Assert.assertEquals(
        "While trying to deploy, function_selector and data can not be both set.",
        conflictingDeployInput.getMessage());
  }

  @Test
  public void testGetJsonString() {
    String str = "";
    String ret = Util.getJsonString(str);
    Assert.assertEquals("", ret);

    String str1 = "{\"owner_address\":\"owner_address\"}";
    String ret1 = Util.getJsonString(str1);
    Assert.assertEquals(str1, ret1);

    String str2 = "owner_address=owner_address&contract_address=contract_address";
    String ret2 = Util.getJsonString(str2);
    String expect =
        "{\"owner_address\":\"owner_address\","
            + "\"contract_address\":\"contract_address\"}";
    Assert.assertEquals(expect, ret2);
  }

}
