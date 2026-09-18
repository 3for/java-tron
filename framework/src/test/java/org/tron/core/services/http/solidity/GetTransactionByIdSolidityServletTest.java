package org.tron.core.services.http.solidity;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.google.protobuf.Any;
import com.google.protobuf.ByteString;
import org.junit.Test;
import org.springframework.mock.web.MockHttpServletResponse;
import org.tron.common.utils.ByteArray;
import org.tron.core.actuator.TransactionFactory;
import org.tron.core.capsule.TransactionCapsule;
import org.tron.core.services.http.BaseHttpTest;
import org.tron.json.JSONObject;
import org.tron.protos.Protocol.Transaction;
import org.tron.protos.Protocol.Transaction.Contract;
import org.tron.protos.Protocol.Transaction.Contract.ContractType;
import org.tron.protos.contract.BalanceContract.TransferContract;

public class GetTransactionByIdSolidityServletTest extends BaseHttpTest {

  private final Transaction transaction = Transaction.newBuilder()
      .setRawData(Transaction.raw.newBuilder().addContract(Contract.newBuilder()
          .setType(ContractType.TransferContract)
          .setParameter(Any.pack(TransferContract.newBuilder()
              .setOwnerAddress(ByteString.copyFrom(ByteArray.fromHexString(
                  "410000000000000000000000000000000000000001")))
              .setToAddress(ByteString.copyFrom(ByteArray.fromHexString(
                  "410000000000000000000000000000000000000002")))
              .setAmount(1000L)
              .build()))))
      .build();
  private final ByteString transactionId = new TransactionCapsule(transaction)
      .getTransactionId().getByteString();
  private final String transactionIdHex = ByteArray.toHexString(transactionId.toByteArray());

  private GetTransactionByIdSolidityServlet servlet;

  @Override
  protected void setUpMocks() throws Exception {
    TransactionFactory.register(ContractType.TransferContract, null, TransferContract.class);
    servlet = new GetTransactionByIdSolidityServlet();
    injectWallet(servlet);
  }

  @Test
  public void testPostReturnsTransactionWhenFound() throws Exception {
    when(wallet.getTransactionById(eq(transactionId))).thenReturn(transaction);
    MockHttpServletResponse response = newResponse();

    servlet.doPost(postRequest("{\"value\":\"" + transactionIdHex + "\"}"), response);

    verify(wallet).getTransactionById(eq(transactionId));
    assertTransaction(response);
  }

  @Test
  public void testGetReturnsTransactionWhenFound() throws Exception {
    when(wallet.getTransactionById(eq(transactionId))).thenReturn(transaction);
    MockHttpServletResponse response = newResponse();

    servlet.doGet(getRequest("value", transactionIdHex), response);

    verify(wallet).getTransactionById(eq(transactionId));
    assertTransaction(response);
  }

  private void assertTransaction(MockHttpServletResponse response) throws Exception {
    JSONObject result = JSONObject.parseObject(response.getContentAsString());
    assertFalse(result.containsKey("Error"));
    assertEquals(transactionIdHex, result.getString("txID"));
    JSONObject contract = result.getJSONObject("raw_data").getJSONArray("contract")
        .getJSONObject(0);
    assertEquals("TransferContract", contract.getString("type"));
    assertEquals(1000L, contract.getJSONObject("parameter").getJSONObject("value")
        .getLongValue("amount"));
  }
}
