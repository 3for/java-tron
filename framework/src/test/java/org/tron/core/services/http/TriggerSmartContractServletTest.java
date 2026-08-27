package org.tron.core.services.http;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.google.protobuf.ByteString;
import org.junit.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.mock.web.MockHttpServletResponse;
import org.tron.common.crypto.ECKey;
import org.tron.common.utils.ByteArray;
import org.tron.core.capsule.TransactionCapsule;
import org.tron.json.JSONObject;
import org.tron.protos.Protocol.Transaction;
import org.tron.protos.contract.SmartContractOuterClass.TriggerSmartContract;

public class TriggerSmartContractServletTest extends BaseHttpTest {

  private final byte[] ownerAddress = new ECKey().getAddress();
  private final byte[] contractAddress = new ECKey().getAddress();
  private TriggerSmartContractServlet servlet;

  @Override
  protected void setUpMocks() throws Exception {
    servlet = new TriggerSmartContractServlet();
    injectWallet(servlet);
    when(wallet.createTransactionCapsule(any(), any()))
        .thenReturn(new TransactionCapsule(MINIMAL_TX));
    when(wallet.triggerContract(any(), any(), any(), any()))
        .thenAnswer(invocation -> ((TransactionCapsule) invocation.getArgument(1)).getInstance());
  }

  @Test
  public void testPostBuildsTriggerAndReturnsSuccessfulTransaction() throws Exception {
    String body = "{\"owner_address\":\"" + ByteArray.toHexString(ownerAddress)
        + "\",\"contract_address\":\"" + ByteArray.toHexString(contractAddress)
        + "\",\"function_selector\":\"test()\",\"fee_limit\":123}";
    MockHttpServletResponse response = newResponse();

    servlet.doPost(postRequest(body), response);

    assertEquals(200, response.getStatus());
    ArgumentCaptor<TriggerSmartContract> triggerCaptor =
        ArgumentCaptor.forClass(TriggerSmartContract.class);
    verify(wallet).createTransactionCapsule(triggerCaptor.capture(),
        eq(org.tron.protos.Protocol.Transaction.Contract.ContractType.TriggerSmartContract));
    TriggerSmartContract trigger = triggerCaptor.getValue();
    assertEquals(ByteString.copyFrom(ownerAddress), trigger.getOwnerAddress());
    assertEquals(ByteString.copyFrom(contractAddress), trigger.getContractAddress());
    assertEquals(4, trigger.getData().size());

    JSONObject json = JSONObject.parseObject(response.getContentAsString());
    JSONObject result = json.getJSONObject("result");
    assertEquals(Boolean.TRUE, result.get("result"));
    assertTrue(json.containsKey("transaction"));
    assertTrue(json.getJSONObject("transaction").containsKey("txID"));
    Number feeLimit = (Number) json.getJSONObject("transaction")
        .getJSONObject("raw_data").get("fee_limit");
    assertEquals(123L, feeLimit.longValue());
  }

  @Test
  public void testMissingOwnerReturnsBusinessErrorWithoutCallingWallet() throws Exception {
    String body = "{\"contract_address\":\"" + ByteArray.toHexString(contractAddress) + "\"}";
    MockHttpServletResponse response = newResponse();

    servlet.doPost(postRequest(body), response);

    assertEquals(200, response.getStatus());
    JSONObject result = JSONObject.parseObject(response.getContentAsString())
        .getJSONObject("result");
    // Protobuf JSON omits scalar fields that hold their default value. A failed Return therefore
    // has no "result" member rather than serializing it as false.
    assertFalse(result.containsKey("result"));
    assertEquals("OTHER_ERROR", result.getString("code"));
    String errorMessage = ByteString.copyFrom(
        ByteArray.fromHexString(result.getString("message"))).toStringUtf8();
    assertEquals(
        "class java.security.InvalidParameterException : owner_address isn't set.", errorMessage);
    verify(wallet, never()).createTransactionCapsule(any(), any());
    verify(wallet, never()).triggerContract(any(), any(), any(), any());
  }
}
