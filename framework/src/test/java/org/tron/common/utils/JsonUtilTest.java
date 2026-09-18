package org.tron.common.utils;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;
import static org.tron.common.utils.JsonUtil.json2Obj;
import static org.tron.common.utils.JsonUtil.obj2Json;

import lombok.Data;
import org.junit.Test;

public class JsonUtilTest {

  @Data
  public static class A {
    private String key;
    private int value;

    public A() {}

    public A(String key, int value) {
      this.key = key;
      this.value = value;
    }
  }

  @Test
  public void test() {
    A a1 = new A();
    a1.setKey("abc");
    a1.setValue(100);

    String jsonString = obj2Json(a1);

    A a2 = JsonUtil.json2Obj(jsonString, A.class);

    assert a2 != null;
    assertEquals("abc", a2.getKey());
    assertEquals(100, a2.getValue());
    assertNull(obj2Json(null));
    assertNull(json2Obj(null, null));


  }

  @Test
  public void testObj2JsonWithCircularReference() {
    Node node = new Node("Node1");
    assertTrue(obj2Json(node).contains("\"name\":\"Node1\""));
    node.setNext(node);

    RuntimeException exception = assertThrows(RuntimeException.class, () -> obj2Json(node));
    assertTrue(exception.getCause() instanceof com.fasterxml.jackson.databind.JsonMappingException);
    assertTrue(exception.getCause().getMessage().contains("Direct self-reference"));
  }

  @Test(expected = RuntimeException.class)
  public void testInvalidJson() {
    String invalidJson = "{invalid: json}";
    json2Obj(invalidJson, String.class);
  }

  public static class Node {
    private String name;
    private org.tron.common.utils.JsonUtilTest.Node next;

    public Node(String name) {
      this.name = name;
    }

    public String getName() {
      return name;
    }

    public Node getNext() {
      return next;
    }

    public void setNext(org.tron.common.utils.JsonUtilTest.Node next) {
      this.next = next;
    }
  }
}
