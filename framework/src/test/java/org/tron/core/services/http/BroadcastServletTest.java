package org.tron.core.services.http;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import org.junit.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.mock.web.MockHttpServletResponse;
import org.tron.api.GrpcAPI;
import org.tron.common.utils.ByteArray;
import org.tron.core.capsule.TransactionCapsule;
import org.tron.json.JSONObject;
import org.tron.protos.Protocol.Transaction;

public class BroadcastServletTest extends BaseHttpTest {

  private static final String TRANSACTION_JSON =
      "{\"signature\":[\"97c825b41c77de2a8bd65b3df55cd4c0df59c307c0187e42321dcc1cc4"
          + "55ddba583dd9502e17cfec5945b34cad0511985a6165999092a6dec84c2bdd97e649fc01\"],"
          + "\"raw_data\":{\"contract\":[{\"parameter\":{\"value\":{\"amount\":1000,"
          + "\"owner_address\":\"41e552f6487585c2b58bc2c9bb4492bc1f17132cd0\","
          + "\"to_address\":\"41d1e7a6bc354106cb410e65ff8b181c600ff14292\"},"
          + "\"type_url\":\"type.googleapis.com/protocol.TransferContract\"},"
          + "\"type\":\"TransferContract\"}],\"ref_block_bytes\":\"267e\","
          + "\"ref_block_hash\":\"9a447d222e8de9f2\",\"expiration\":1530893064000,"
          + "\"timestamp\":1530893006233}}";

  private BroadcastServlet servlet;

  @Override
  protected void setUpMocks() throws Exception {
    servlet = new BroadcastServlet();
    injectWallet(servlet);
    when(wallet.broadcastTransaction(any())).thenReturn(GrpcAPI.Return.newBuilder()
        .setResult(true)
        .setCode(GrpcAPI.Return.response_code.SUCCESS)
        .build());
  }

  @Test
  public void testPostBroadcastsParsedTransactionAndReturnsItsId() throws Exception {
    MockHttpServletResponse response = newResponse();

    servlet.doPost(postRequest(TRANSACTION_JSON), response);

    assertEquals(200, response.getStatus());
    ArgumentCaptor<Transaction> transactionCaptor = ArgumentCaptor.forClass(Transaction.class);
    verify(wallet).broadcastTransaction(transactionCaptor.capture());
    Transaction transaction = transactionCaptor.getValue();
    assertEquals(1, transaction.getRawData().getContractCount());
    assertEquals(Transaction.Contract.ContractType.TransferContract,
        transaction.getRawData().getContract(0).getType());

    JSONObject result = JSONObject.parseObject(response.getContentAsString());
    assertEquals(Boolean.TRUE, result.get("result"));
    assertFalse(result.containsKey("Error"));
    assertEquals(ByteArray.toHexString(new TransactionCapsule(transaction)
        .getTransactionId().getBytes()), result.getString("txid"));
  }

  @Test
  public void testMalformedTransactionReturnsBusinessError() throws Exception {
    MockHttpServletResponse response = newResponse();

    servlet.doPost(postRequest("{}"), response);

    assertEquals(200, response.getStatus());
    JSONObject result = JSONObject.parseObject(response.getContentAsString());
    assertTrue(result.containsKey("Error"));
  }
}
