import test from "node:test";
import assert from "node:assert/strict";
import {
  processLabel,
  sourceField,
  publicationDate,
  processLink,
  publicationContent,
  movementDate,
  stfCollectionLink,
  stfIncident,
  stfLinks,
} from "./detail-presentation.mjs";

test("o número com máscara da fonte prevalece sobre números sem formatação", () => {
  assert.equal(
    processLabel(
      {
        numeroprocessocommascara: " 1009769-04.2026.8.26.0002 ",
        numero_processo: "10563132320218260100",
      },
      "00000000120268260000",
    ),
    "1009769-04.2026.8.26.0002",
  );
});

test("vinte dígitos recebem a máscara CNJ sem perder zeros", () => {
  assert.equal(
    processLabel({ numero_processo: "10563132320218260100" }),
    "1056313-23.2021.8.26.0100",
  );
  assert.equal(
    processLabel({ numeroprocessocommascara: " " }, "00000000120268260000"),
    "0000000-01.2026.8.26.0000",
  );
  assert.equal(
    processLabel({}, "00000000000000000000"),
    "0000000-00.0000.0.00.0000",
  );
});

test("números já formatados não são reinterpretados", () => {
  assert.equal(
    processLabel({}, " 1009769-04.2026.8.26.0002 "),
    "1009769-04.2026.8.26.0002",
  );
});

test("metadados são somente strings fornecidas, sem inferir campos ausentes", () => {
  assert.equal(
    sourceField({ nomeOrgao: "  Vara de Família  " }, "nomeOrgao"),
    "Vara de Família",
  );
  for (const payload of [
    undefined,
    null,
    {},
    [],
    { nomeOrgao: " " },
    { nomeOrgao: 123 },
  ]) {
    assert.equal(sourceField(payload, "nomeOrgao"), "Não fornecido");
  }
  assert.equal(
    sourceField(Object.create({ nomeOrgao: "herdado" }), "nomeOrgao"),
    "Não fornecido",
  );
  assert.equal(processLabel({}), "Não fornecido");
  assert.equal(
    processLabel({ numero_processo: 10563132320218260100 }),
    "Não fornecido",
  );
  assert.equal(publicationDate({}), "Não fornecido");
  assert.equal(processLink({}), null);
  assert.equal(sourceField({ court: "TJSP" }, "nomeOrgao"), "Não fornecido");
  assert.equal(publicationDate({ created_at: "2026-10-29" }), "Não fornecido");
  assert.equal(processLink({ url: "https://example.com/processo" }), null);
});

test("data de disponibilização é apresentada como data civil, sem deslocamento de fuso", () => {
  assert.equal(
    publicationDate({ data_disponibilizacao: "2026-10-29" }),
    "29/10/2026",
  );
  assert.equal(
    publicationDate({ data_disponibilizacao: " 2024-02-29 " }),
    "29/02/2024",
  );
  assert.equal(
    publicationDate({ data_disponibilizacao: "2000-02-29" }),
    "29/02/2000",
  );
});

test("datas inválidas não transbordam para outro mês ou ano", () => {
  for (const value of [
    "2026-02-29",
    "1900-02-29",
    "2026-04-31",
    "2026-13-01",
    "2026-00-01",
    "2026-01-00",
    "2026-01-32",
    "0000-01-01",
    "2026-1-1",
    "29/10/2026",
    "2026-10-29T00:00:00Z",
    "invalid",
    "",
    null,
    20261029,
  ]) {
    assert.equal(
      publicationDate({ data_disponibilizacao: value }),
      "Não fornecido",
      String(value),
    );
  }
});

test("o link da fonte aceita somente URLs externas HTTP ou HTTPS sem credenciais", () => {
  assert.equal(
    processLink({ link: " https://www.dje.tjsp.jus.br " }),
    "https://www.dje.tjsp.jus.br/",
  );
  assert.equal(
    processLink({ link: "http://example.com/processo?id=1#texto" }),
    "http://example.com/processo?id=1#texto",
  );
  for (const value of [
    "javascript:alert(1)",
    "JaVaScRiPt:alert(1)",
    "data:text/html,<script>alert(1)</script>",
    "ftp://example.com",
    "https://user:password@example.com",
    "https://user@example.com",
    "https://:password@example.com",
    "/processo/1",
    "//example.com/processo",
    "not a URL",
    "",
    null,
    123,
  ]) {
    assert.equal(processLink({ link: value }), null, String(value));
  }
});

test("o PDF real da fonte mantém rótulo, destino exato e texto ao redor", () => {
  const href =
    "https://www.tjsp.jus.br/download/EPROC/ManuaisPublicoExterno/1.1-EPROC_ADVOGADO-Primeiros_passos_no_sistema_eproc_04.04.25.pdf";
  const parts = [
    { text: "Material de apoio disponível em: " },
    { text: " EPROC_ADVOGADO-Primeiros_passos_no_sistema.PDF ", href },
    { text: "\nPróximo parágrafo & partes." },
  ];
  const texto = parts.map((part) => part.text).join("");
  assert.deepEqual(publicationContent({ texto, texto_parts: parts }), parts);
  assert.equal(
    publicationContent({ texto, texto_parts: parts })
      .map((part) => part.text)
      .join(""),
    texto,
  );
});

test("links perigosos ficam inertes sem perder seu rótulo", () => {
  for (const href of [
    "javascript:alert(1)",
    "JaVaScRiPt:alert(1)",
    "java\nscript:alert(1)",
    "data:text/html,<script>alert(1)</script>",
    "file:///etc/passwd",
    "https://user:password@example.com",
    "https://user@example.com",
    "//example.com/documento",
    "/documento",
    "https://example.com/\u0000",
  ]) {
    assert.deepEqual(
      publicationContent({
        texto: "Antes documento depois",
        texto_parts: [
          { text: "Antes " },
          { text: "documento", href, onclick: "alert(1)" },
          { text: " depois" },
        ],
      }),
      [{ text: "Antes " }, { text: "documento" }, { text: " depois" }],
      href,
    );
  }
});

test("texto comum e marcação literal continuam texto, sem interpretar ou inventar links", () => {
  const texto =
    "<script>exemplo</script> &amp; <a href='javascript:x'>exemplo</a>\n\nOutro parágrafo.";
  assert.deepEqual(publicationContent({ texto }), [{ text: texto }]);
  assert.deepEqual(publicationContent({ texto: "PDF sem destino" }), [
    { text: "PDF sem destino" },
  ]);
  assert.deepEqual(publicationContent({ texto: null }), []);
});

test("metadados incompletos ou divergentes não substituem o texto da publicação", () => {
  for (const texto_parts of [
    null,
    {},
    [],
    [{ text: "outro" }],
    [{ text: 123 }],
    [{ text: "original" }, null],
  ]) {
    assert.deepEqual(publicationContent({ texto: "original", texto_parts }), [
      { text: "original" },
    ]);
  }
});

test("apresentação derivada de caderno preserva o original e não expõe HTML como nós", () => {
  const texto =
    "<p>Primeiro <a href='https://example.com/manual.pdf'>manual</a></p>";
  const payload = {
    texto,
    texto_plain: "Primeiro manual",
    texto_parts: [
      { text: "Primeiro " },
      {
        text: "manual",
        href: "https://example.com/manual.pdf",
        target: "_self",
      },
    ],
  };
  assert.deepEqual(publicationContent(payload), [
    { text: "Primeiro " },
    { text: "manual", href: "https://example.com/manual.pdf" },
  ]);
  assert.equal(payload.texto, texto);
});

test("identificação STF preserva classe e número quando não há CNJ", () => {
  assert.equal(
    processLabel({ numero_processo: null }, null, "Rcl 101463"),
    "Rcl 101463",
  );
  assert.equal(
    processLabel(
      { numero_processo: "01882631920261000000" },
      null,
      "Rcl 101463",
    ),
    "0188263-19.2026.1.00.0000",
  );
});

test("data civil de andamento não usa disponibilização e rejeita datas inválidas", () => {
  assert.equal(
    movementDate({
      stf: { data_andamento: "2026-05-05" },
      data_disponibilizacao: "2026-05-06",
    }),
    "05/05/2026",
  );
  assert.equal(
    movementDate({ stf: { data_andamento: "2026-02-29" } }),
    "Não fornecido",
  );
});

test("origem STF e links associados preservam rótulos sem abrir destinos inseguros", () => {
  const payload = {
    link: "https://portal.stf.jus.br/processos/detalhe.asp?incidente=7728350",
    stf: {
      url_coleta:
        "https://portal.stf.jus.br/processos/abaAndamentos.asp?incidente=7728350",
      incidente: 7728350,
      links: [
        {
          url: "https://example.com/decisao.pdf",
          rotulo: "Decisão",
          referencia_original: "/decisao.pdf",
        },
        {
          url: "javascript:alert(1)",
          rotulo: "Malicioso",
          referencia_original: "javascript:alert(1)",
        },
        {
          url: "https://user@example.com/a",
          referencia_original: "referência",
        },
        { url: "https://example.com/\npath", rotulo: "Controle" },
      ],
    },
  };
  assert.equal(processLink(payload), payload.link);
  assert.equal(stfCollectionLink(payload), payload.stf.url_coleta);
  assert.equal(stfIncident(payload), "7728350");
  assert.deepEqual(stfLinks(payload), [
    { text: "Decisão", href: "https://example.com/decisao.pdf" },
    { text: "Malicioso" },
    { text: "referência" },
    { text: "Controle" },
  ]);
  assert.equal(
    processLink({
      stf: { url_coleta: "https://example.com/aba" },
      link: "javascript:alert(1)",
    }),
    null,
  );
  assert.equal(
    stfCollectionLink({ stf: { url_coleta: "https://x.test/\n" } }),
    null,
  );
  assert.deepEqual(
    stfLinks({ stf: { links: [null, 1, {}, { url: "https://example.com" }] } }),
    [{ text: "https://example.com", href: "https://example.com" }],
  );
});
