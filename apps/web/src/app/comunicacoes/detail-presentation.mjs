const NOT_PROVIDED = "Não fornecido";

function field(payload, key) {
  if (
    payload === null ||
    typeof payload !== "object" ||
    Array.isArray(payload) ||
    !Object.hasOwn(payload, key)
  ) {
    return "";
  }
  return typeof payload[key] === "string" ? payload[key].trim() : "";
}

export function sourceField(payload, key) {
  return field(payload, key) || NOT_PROVIDED;
}

export function processLabel(payload, fallback) {
  const masked = field(payload, "numeroprocessocommascara");
  if (masked) return masked;

  const number =
    field(payload, "numero_processo") ||
    (typeof fallback === "string" ? fallback.trim() : "");
  if (!number) return NOT_PROVIDED;
  return /^\d{20}$/.test(number)
    ? number.replace(
        /^(\d{7})(\d{2})(\d{4})(\d)(\d{2})(\d{4})$/,
        "$1-$2.$3.$4.$5.$6",
      )
    : number;
}

export function publicationDate(payload) {
  const value = field(payload, "data_disponibilizacao");
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return NOT_PROVIDED;

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const leapYear = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const daysInMonth = [
    31,
    leapYear ? 29 : 28,
    31,
    30,
    31,
    30,
    31,
    31,
    30,
    31,
    30,
    31,
  ];
  if (
    year === 0 ||
    month < 1 ||
    month > 12 ||
    day < 1 ||
    day > daysInMonth[month - 1]
  ) {
    return NOT_PROVIDED;
  }
  return `${match[3]}/${match[2]}/${match[1]}`;
}

export function processLink(payload) {
  const href = safeHref(field(payload, "link"));
  return href ? new URL(href).href : null;
}

function safeHref(value) {
  if (
    typeof value !== "string" ||
    !/^https?:\/\//i.test(value.trim()) ||
    /[\u0000-\u001f\u007f]/.test(value)
  ) {
    return null;
  }
  try {
    const url = new URL(value);
    if (
      (url.protocol !== "http:" && url.protocol !== "https:") ||
      url.username ||
      url.password
    ) {
      return null;
    }
    return value.trim();
  } catch {
    return null;
  }
}

export function publicationContent(payload) {
  if (
    payload === null ||
    typeof payload !== "object" ||
    Array.isArray(payload) ||
    typeof payload.texto !== "string"
  ) {
    return [];
  }
  const fallback = [{ text: payload.texto }];
  if (
    !Object.hasOwn(payload, "texto_parts") ||
    !Array.isArray(payload.texto_parts) ||
    payload.texto_parts.length === 0
  ) {
    return fallback;
  }
  const parts = [];
  for (const part of payload.texto_parts) {
    if (
      part === null ||
      typeof part !== "object" ||
      Array.isArray(part) ||
      !Object.hasOwn(part, "text") ||
      typeof part.text !== "string"
    ) {
      return fallback;
    }
    const href = Object.hasOwn(part, "href") ? safeHref(part.href) : null;
    parts.push(href ? { text: part.text, href } : { text: part.text });
  }
  const expected = Object.hasOwn(payload, "texto_plain")
    ? payload.texto_plain
    : payload.texto;
  return parts.map((part) => part.text).join("") === expected
    ? parts
    : fallback;
}
