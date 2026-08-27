package org.tron.core.services.http;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.google.protobuf.ByteString;
import org.junit.Test;
import org.springframework.mock.web.MockHttpServletResponse;
import org.tron.api.GrpcAPI.Address;
import org.tron.api.GrpcAPI.Node;
import org.tron.api.GrpcAPI.NodeList;
import org.tron.json.JSONArray;
import org.tron.json.JSONObject;

public class ListNodesServletTest extends BaseHttpTest {

  private ListNodesServlet servlet;

  @Override
  protected void setUpMocks() throws Exception {
    servlet = new ListNodesServlet();
    injectWallet(servlet);
    when(wallet.listNodes()).thenReturn(NodeList.newBuilder()
        .addNodes(Node.newBuilder().setAddress(Address.newBuilder()
            .setHost(ByteString.copyFromUtf8("127.0.0.1"))
            .setPort(18888)))
        .build());
  }

  @Test
  public void testPostReturnsNodeList() throws Exception {
    MockHttpServletResponse response = newResponse();

    servlet.doPost(postRequest("{}"), response);

    assertEquals(200, response.getStatus());
    verify(wallet).listNodes();
    JSONObject json = JSONObject.parseObject(response.getContentAsString());
    assertFalse(json.containsKey("Error"));
    JSONArray nodes = json.getJSONArray("nodes");
    assertEquals(1, nodes.size());
    assertEquals(18888L, ((Number) nodes.getJSONObject(0)
        .getJSONObject("address").get("port")).longValue());
  }

  @Test
  public void testGetReturnsEmptyObjectWhenWalletReturnsNull() throws Exception {
    when(wallet.listNodes()).thenReturn(null);
    MockHttpServletResponse response = newResponse();

    servlet.doGet(getRequest("visible", "true"), response);

    assertEquals(200, response.getStatus());
    verify(wallet).listNodes();
    assertEquals("{}", response.getContentAsString().trim());
  }
}
