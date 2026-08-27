package org.tron.core.services.http;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.google.protobuf.ByteString;
import org.junit.Test;
import org.springframework.mock.web.MockHttpServletResponse;
import org.tron.api.GrpcAPI.AssetIssueList;
import org.tron.json.JSONArray;
import org.tron.json.JSONObject;
import org.tron.protos.contract.AssetIssueContractOuterClass.AssetIssueContract;

public class GetAssetIssueListServletTest extends BaseHttpTest {

  private GetAssetIssueListServlet servlet;

  @Override
  protected void setUpMocks() throws Exception {
    servlet = new GetAssetIssueListServlet();
    injectWallet(servlet);
    when(wallet.getAssetIssueList()).thenReturn(AssetIssueList.newBuilder()
        .addAssetIssue(AssetIssueContract.newBuilder()
            .setName(ByteString.copyFromUtf8("asset"))
            .setTotalSupply(5000L))
        .build());
  }

  @Test
  public void testPostReturnsAssetList() throws Exception {
    MockHttpServletResponse response = newResponse();

    servlet.doPost(postRequest("{}"), response);

    assertEquals(200, response.getStatus());
    verify(wallet).getAssetIssueList();
    JSONObject json = JSONObject.parseObject(response.getContentAsString());
    assertFalse(json.containsKey("Error"));
    JSONArray assets = json.getJSONArray("assetIssue");
    assertEquals(1, assets.size());
    assertEquals(5000L, ((Number) assets.getJSONObject(0).get("total_supply")).longValue());
  }

  @Test
  public void testGetReturnsEmptyObjectWhenWalletReturnsNull() throws Exception {
    when(wallet.getAssetIssueList()).thenReturn(null);
    MockHttpServletResponse response = newResponse();

    servlet.doGet(getRequest("visible", "true"), response);

    assertEquals(200, response.getStatus());
    verify(wallet).getAssetIssueList();
    assertEquals("{}", response.getContentAsString().trim());
  }
}
