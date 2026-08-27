package org.tron.core.services.http;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.google.protobuf.ByteString;
import org.junit.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.mock.web.MockHttpServletResponse;
import org.tron.api.GrpcAPI.EstimateEnergyMessage;
import org.tron.api.GrpcAPI.Return;
import org.tron.common.crypto.ECKey;
import org.tron.common.utils.ByteArray;
import org.tron.core.capsule.TransactionCapsule;
import org.tron.core.exception.ContractValidateException;
import org.tron.json.JSONObject;
import org.tron.protos.Protocol.Transaction.Contract.ContractType;
import org.tron.protos.contract.SmartContractOuterClass.TriggerSmartContract;

public class EstimateEnergyServletTest extends BaseHttpTest {

  private final byte[] ownerAddress = new ECKey().getAddress();
  private final byte[] contractAddress = new ECKey().getAddress();
  private EstimateEnergyServlet servlet;

  @Override
  protected void setUpMocks() throws Exception {
    servlet = new EstimateEnergyServlet();
    injectWallet(servlet);
  }

  @Test
  public void testPostBuildsTriggerAndReturnsEstimatedEnergy() throws Exception {
    when(wallet.createTransactionCapsule(any(), any()))
        .thenReturn(new TransactionCapsule(MINIMAL_TX));
    when(wallet.estimateEnergy(any(), any(), any(), any(), any()))
        .thenAnswer(invocation -> {
          Return.Builder result = invocation.getArgument(3);
          EstimateEnergyMessage.Builder estimate = invocation.getArgument(4);
          result.setResult(true).setCode(Return.response_code.SUCCESS);
          estimate.setEnergyRequired(321L);
          return MINIMAL_TX;
        });
    String body = "{\"owner_address\":\"" + ByteArray.toHexString(ownerAddress)
        + "\",\"contract_address\":\"" + ByteArray.toHexString(contractAddress)
        + "\",\"function_selector\":\"test()\"}";
    MockHttpServletResponse response = newResponse();

    servlet.doPost(postRequest(body), response);

    assertEquals(200, response.getStatus());
    ArgumentCaptor<TriggerSmartContract> triggerCaptor =
        ArgumentCaptor.forClass(TriggerSmartContract.class);
    verify(wallet).createTransactionCapsule(triggerCaptor.capture(),
        eq(ContractType.TriggerSmartContract));
    TriggerSmartContract trigger = triggerCaptor.getValue();
    assertEquals(ByteString.copyFrom(ownerAddress), trigger.getOwnerAddress());
    assertEquals(ByteString.copyFrom(contractAddress), trigger.getContractAddress());
    assertEquals(4, trigger.getData().size());

    JSONObject json = JSONObject.parseObject(response.getContentAsString());
    assertEquals(321L, ((Number) json.get("energy_required")).longValue());
    assertEquals(Boolean.TRUE, json.getJSONObject("result").get("result"));
  }

  @Test
  public void testContractValidationErrorIsReturned() throws Exception {
    when(wallet.createTransactionCapsule(any(), any()))
        .thenThrow(new ContractValidateException("invalid contract"));
    String body = "{\"owner_address\":\"" + ByteArray.toHexString(ownerAddress)
        + "\",\"contract_address\":\"" + ByteArray.toHexString(contractAddress) + "\"}";
    MockHttpServletResponse response = newResponse();

    servlet.doPost(postRequest(body), response);

    JSONObject result = JSONObject.parseObject(response.getContentAsString())
        .getJSONObject("result");
    assertFalse(result.containsKey("result"));
    assertEquals("CONTRACT_VALIDATE_ERROR", result.getString("code"));
    assertEquals("invalid contract", decodeMessage(result));
    verify(wallet, never()).estimateEnergy(any(), any(), any(), any(), any());
  }

  @Test
  public void testMissingOwnerReturnsBusinessErrorWithoutCallingWallet() throws Exception {
    String body = "{\"contract_address\":\"" + ByteArray.toHexString(contractAddress) + "\"}";
    MockHttpServletResponse response = newResponse();

    servlet.doPost(postRequest(body), response);

    JSONObject result = JSONObject.parseObject(response.getContentAsString())
        .getJSONObject("result");
    assertFalse(result.containsKey("result"));
    assertEquals("OTHER_ERROR", result.getString("code"));
    assertEquals("class java.security.InvalidParameterException : owner_address isn't set.",
        decodeMessage(result));
    verify(wallet, never()).createTransactionCapsule(any(), any());
    verify(wallet, never()).estimateEnergy(any(), any(), any(), any(), any());
  }

  private static String decodeMessage(JSONObject result) {
    return ByteString.copyFrom(ByteArray.fromHexString(result.getString("message"))).toStringUtf8();
  }
}
