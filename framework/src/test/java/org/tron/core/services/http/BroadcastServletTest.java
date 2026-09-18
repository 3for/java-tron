package org.tron.core.services.http;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.google.protobuf.Any;
import com.google.protobuf.ByteString;
import java.math.BigInteger;
import org.junit.Test;
import org.springframework.mock.web.MockHttpServletResponse;
import org.tron.api.GrpcAPI.Return;
import org.tron.common.crypto.ECKey;
import org.tron.common.utils.ByteArray;
import org.tron.core.actuator.TransactionFactory;
import org.tron.core.capsule.TransactionCapsule;
import org.tron.json.JSONObject;
import org.tron.protos.Protocol.Transaction;
import org.tron.protos.Protocol.Transaction.Contract;
import org.tron.protos.Protocol.Transaction.Contract.ContractType;
import org.tron.protos.contract.BalanceContract.TransferContract;

public class BroadcastServletTest extends BaseHttpTest {

  private static final String RECIPIENT = "410000000000000000000000000000000000000002";
  private Transaction transaction;
  private String requestBody;
  private BroadcastServlet servlet;

  @Override
  protected void setUpMocks() throws Exception {
    TransactionFactory.register(ContractType.TransferContract, null, TransferContract.class);
    servlet = new BroadcastServlet();
    injectWallet(servlet);
    ECKey owner = ECKey.fromPrivate(BigInteger.ONE);
    long now = System.currentTimeMillis();
    Transaction unsigned = Transaction.newBuilder()
        .setRawData(Transaction.raw.newBuilder().setTimestamp(now).setExpiration(now + 60_000L)
            .addContract(Contract.newBuilder()
                .setType(ContractType.TransferContract)
                .setParameter(Any.pack(TransferContract.newBuilder()
                    .setOwnerAddress(ByteString.copyFrom(owner.getAddress()))
                    .setToAddress(ByteString.copyFrom(ByteArray.fromHexString(RECIPIENT)))
                    .setAmount(1000L)
                    .build()))))
        .build();
    TransactionCapsule capsule = new TransactionCapsule(unsigned);
    capsule.sign(owner.getPrivKeyBytes());
    transaction = capsule.getInstance();
    requestBody = Util.printTransaction(transaction, false);
  }

  @Test
  public void testPostReturnsBroadcastResultAndTransactionId() throws Exception {
    when(wallet.broadcastTransaction(eq(transaction)))
        .thenReturn(Return.newBuilder().setResult(true).build());

    MockHttpServletResponse response = newResponse();
    servlet.doPost(postRequest(requestBody), response);

    verify(wallet).broadcastTransaction(eq(transaction));
    JSONObject result = JSONObject.parseObject(response.getContentAsString());
    assertEquals(Boolean.TRUE, result.getBoolean("result"));
    assertEquals(new TransactionCapsule(transaction).getTransactionId().toString(),
        result.getString("txid"));
    assertFalse(result.containsKey("Error"));
  }
}
