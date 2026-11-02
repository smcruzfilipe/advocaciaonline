require "cgi"
require "mail"

# Banani's email layout, rendered with inline styles and presentation tables:
# no Tailwind runtime, remote fonts, tracking assets or illustrative links.
class EmailTemplate
  def self.apply(message, text:, title:, action_label:, action_url:, status: nil)
    action = action_html(action_label, action_url)
    paragraphs = text.split(/\n[ \t]*\n/).map(&:strip).reject(&:empty?)
    has_action = paragraphs.include?(action_url)
    content = paragraphs.map do |paragraph|
      if paragraph == action_url
        action
      else
        "<p style=\"margin:0 0 20px;color:#111111;font-size:14px;line-height:1.7;\">#{escape(paragraph).gsub("\n", "<br>")}</p>"
      end
    end.join("\n")
    content += action unless has_action
    status_row = if status
      <<~HTML
        <tr><td bgcolor="#f0fdf4" style="padding:16px 32px;border-left:4px solid #16a34a;color:#166534;font-size:14px;font-weight:bold;line-height:1.5;">#{escape(status)}</td></tr>
      HTML
    end

    html = <<~HTML
      <!doctype html>
      <html lang="pt-BR">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta name="color-scheme" content="light">
          <title>#{escape(title)}</title>
          <style>
            @media only screen and (max-width:480px) {
              .email-outer { padding:16px 8px !important; }
              .email-content { padding:24px 20px !important; }
            }
          </style>
        </head>
        <body style="margin:0;padding:0;background-color:#e8e8e8;color:#111111;font-family:'IBM Plex Sans',Arial,Helvetica,sans-serif;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="#e8e8e8">
            <tr><td align="center" class="email-outer" style="padding:32px;">
              <!--[if mso]><table role="presentation" width="672" cellpadding="0" cellspacing="0" border="0"><tr><td><![endif]-->
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="#ffffff" style="max-width:672px;table-layout:fixed;">
                <tr><td bgcolor="#111111" class="email-content" style="padding:24px 32px;">
                  <h1 style="margin:0;color:#ffffff;font-family:'IBM Plex Sans',Arial,Helvetica,sans-serif;font-size:22px;line-height:1.4;font-weight:600;">Advocacia Online</h1>
                  <p style="margin:6px 0 0;color:#d4d4d4;font-size:12px;line-height:1.5;">#{escape(title)}</p>
                </td></tr>
                #{status_row}
                <tr><td class="email-content" style="padding:32px;word-wrap:break-word;overflow-wrap:anywhere;">
                  <p style="margin:0 0 20px;font-size:16px;line-height:1.5;">Olá,</p>
                  #{content}
                  <div style="border-top:1px solid #d4d4d4;padding-top:20px;margin-top:8px;">
                    <p style="margin:0;color:#737373;font-size:12px;line-height:1.7;">Esta é uma mensagem automática. Não responda a este e-mail.</p>
                  </div>
                </td></tr>
                <tr><td align="center" bgcolor="#f0f0f0" class="email-content" style="padding:24px 32px;border-top:1px solid #d4d4d4;">
                  <p style="margin:0;color:#666666;font-size:12px;line-height:1.7;">Advocacia Online</p>
                </td></tr>
              </table>
              <!--[if mso]></td></tr></table><![endif]-->
            </td></tr>
          </table>
        </body>
      </html>
    HTML

    message.charset = "UTF-8"
    message.text_part = Mail::Part.new do
      content_type "text/plain; charset=UTF-8"
      body text
    end
    message.html_part = Mail::Part.new do
      content_type "text/html; charset=UTF-8"
      body html
    end
    message
  end

  def self.action_html(label, url)
    <<~HTML
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:8px 0 24px;table-layout:fixed;">
        <tr><td style="padding:4px 0 20px;">
          <table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr><td bgcolor="#111111" style="mso-padding-alt:14px 24px;">
            <a href="#{escape(url)}" style="display:inline-block;padding:14px 24px;color:#ffffff;background-color:#111111;font-size:14px;font-weight:bold;line-height:1.5;text-decoration:none;">#{escape(label)}</a>
          </td></tr></table>
        </td></tr>
        <tr><td style="padding-bottom:8px;color:#737373;font-size:12px;line-height:1.7;">Ou copie e cole este link no seu navegador:</td></tr>
        <tr><td bgcolor="#f5f5f5" style="padding:12px;border:1px solid #d4d4d4;word-break:break-all;overflow-wrap:anywhere;">
          <a href="#{escape(url)}" style="color:#2563eb;font-family:Consolas,monospace;font-size:12px;line-height:1.7;text-decoration:underline;word-break:break-all;overflow-wrap:anywhere;">#{escape(url)}</a>
        </td></tr>
      </table>
    HTML
  end
  private_class_method :action_html

  def self.escape(value)
    CGI.escapeHTML(value)
  end
  private_class_method :escape
end
