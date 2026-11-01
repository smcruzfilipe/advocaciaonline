import assert from "node:assert/strict";
import { test } from "node:test";
import {
  normalizeWhatsappPhone,
  whatsappInvitationUrl,
} from "./whatsapp-invitation.ts";

test("normaliza telefone internacional e rejeita entradas inválidas", () => {
  assert.equal(normalizeWhatsappPhone("+55 (11) 99266-9299"), "5511992669299");
  assert.equal(normalizeWhatsappPhone("12345678"), "12345678");
  assert.equal(normalizeWhatsappPhone("123456789012345"), "123456789012345");
  for (const phone of [
    "",
    "1234567",
    "1234567890123456",
    "55 11 abc 9999-9999",
    "55+1199999999",
  ])
    assert.equal(normalizeWhatsappPhone(phone), null);
});

test("codifica mensagem e telefone na URL de compartilhamento", () => {
  const url = new URL(
    whatsappInvitationUrl(
      "5511992669299",
      "https://exemplo.test/primeiro-acesso?token=a&outro=b",
      "02/11/2026, 15:30",
    ),
  );
  assert.equal(url.origin + url.pathname, "https://api.whatsapp.com/send/");
  assert.equal(url.searchParams.get("phone"), "5511992669299");
  assert.equal(url.searchParams.get("type"), "phone_number");
  assert.equal(url.searchParams.get("app_absent"), "0");
  assert.ok(
    url.searchParams
      .get("text")
      .split("\n")
      .includes("https://exemplo.test/primeiro-acesso?token=a&outro=b"),
  );
  assert.equal(url.searchParams.has("outro"), false);
});
