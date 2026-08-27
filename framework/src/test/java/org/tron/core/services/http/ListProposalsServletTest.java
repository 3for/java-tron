package org.tron.core.services.http;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import org.junit.Test;
import org.springframework.mock.web.MockHttpServletResponse;
import org.tron.api.GrpcAPI.ProposalList;
import org.tron.json.JSONArray;
import org.tron.json.JSONObject;
import org.tron.protos.Protocol.Proposal;

public class ListProposalsServletTest extends BaseHttpTest {

  private ListProposalsServlet servlet;

  @Override
  protected void setUpMocks() throws Exception {
    servlet = new ListProposalsServlet();
    injectWallet(servlet);
    when(wallet.getProposalList()).thenReturn(ProposalList.newBuilder()
        .addProposals(Proposal.newBuilder().setProposalId(7L))
        .build());
  }

  @Test
  public void testPostReturnsProposalList() throws Exception {
    MockHttpServletResponse response = newResponse();

    servlet.doPost(postRequest("{}"), response);

    assertEquals(200, response.getStatus());
    verify(wallet).getProposalList();
    JSONObject json = JSONObject.parseObject(response.getContentAsString());
    assertFalse(json.containsKey("Error"));
    JSONArray proposals = json.getJSONArray("proposals");
    assertEquals(1, proposals.size());
    assertEquals(7L, ((Number) proposals.getJSONObject(0).get("proposal_id")).longValue());
  }

  @Test
  public void testGetReturnsEmptyObjectWhenWalletReturnsNull() throws Exception {
    when(wallet.getProposalList()).thenReturn(null);
    MockHttpServletResponse response = newResponse();

    servlet.doGet(getRequest("visible", "true"), response);

    assertEquals(200, response.getStatus());
    verify(wallet).getProposalList();
    assertEquals("{}", response.getContentAsString().trim());
  }
}
