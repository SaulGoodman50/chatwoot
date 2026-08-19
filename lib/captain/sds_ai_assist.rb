# SDS patch: laat de AI-knop in de reply box op onze eigen Claude-endpoint
# draaien in plaats van op OpenAI.
#
# Waarom als prepend op de basisservice en niet per service: elke taak
# (samenvatten, reactie voorstellen, herschrijven, follow-up) loopt via
# `make_api_call`, en `event_name` zegt precies welke knop de agent indrukte.
# Eén onderschepping dekt dus alle knoppen, en toekomstige Chatwoot-updates
# aan de losse services raken deze patch niet.
#
# De prompts van Chatwoot (config/../openai_prompts/*.liquid) gebruiken we
# bewust NIET: onze endpoint heeft de kennisbank en de huisstijl van de
# supportbot, zodat een voorgesteld antwoord dezelfde afspraken noemt als de
# bot die 's nachts zelf antwoordt. We sturen alleen de kale context mee.
#
# Config (Railway):
#   AI_ASSIST_URL   https://www.studentdelivery.nl/api/integrations/chatwoot/assist
#   AI_ASSIST_TOKEN CHATWOOT_WEBHOOK_SECRET; gaat als x-webhook-token mee, dus
#                   niet in de querystring waar hij in access-logs zou landen
#
# Staat AI_ASSIST_URL leeg, dan valt alles terug op het originele gedrag
# (OpenAI), zodat deze patch niets breekt als de variabele ontbreekt.
module Captain::SdsAiAssist
  REQUEST_TIMEOUT = 55

  # Chatwoot heeft geen vertaalsleutel voor een mislukte AI-actie (captain.failed
  # bestaat niet), en onze medewerkers lezen Nederlands. Vandaar een vaste tekst
  # in plaats van I18n.
  FALLBACK_ERROR = 'AI-hulp is even niet beschikbaar. Probeer het zo nog eens.'.freeze

  # De knoppen die onze endpoint kent. Alles daarbuiten (label_suggestion,
  # csat-analyse, overview) laten we ongemoeid naar de originele route gaan.
  SUPPORTED_EVENTS = %w[
    summarize
    reply_suggestion
    fix_spelling_grammar
    improve
    professional
    casual
    friendly
    confident
    straightforward
    follow_up
  ].freeze

  private

  def make_api_call(messages:, model: nil, feature: nil, schema: nil, tools: [])
    return super unless sds_assist_applies?(schema: schema, tools: tools)

    result = sds_assist_call(messages)
    # Dezelfde staart als de originele route: zonder deze context toont de UI wel
    # het bijschaaf-veld onder het resultaat, maar doet versturen niets.
    return result unless build_follow_up_context? && result[:message].present?

    result.merge(follow_up_context: build_follow_up_context(messages, result))
  rescue StandardError => e
    # Nooit de knop laten omvallen op een netwerk- of parseerfout: log het en
    # geef de medewerker een leesbare melding.
    Rails.logger.error "[SDS][assist] #{event_name} failed: #{e.message}"
    { error: FALLBACK_ERROR, error_code: 502 }
  end

  def sds_assist_applies?(schema:, tools:)
    return false if sds_assist_url.blank?
    # Gestructureerde uitvoer en tool-gebruik laten we aan de originele route:
    # onze endpoint geeft platte tekst terug.
    return false if schema.present? || tools.present?

    SUPPORTED_EVENTS.include?(event_name.to_s)
  end

  def sds_assist_call(messages)
    response = HTTParty.post(
      sds_assist_url,
      headers: { 'Content-Type' => 'application/json', 'x-webhook-token' => sds_assist_token },
      body: sds_assist_payload(messages).to_json,
      timeout: REQUEST_TIMEOUT
    )

    body = response.parsed_response || {}
    unless response.success?
      Rails.logger.warn "[SDS][assist] #{event_name} → HTTP #{response.code}"
      return { error: body['error'].presence || FALLBACK_ERROR, error_code: response.code }
    end

    message = body['message'].to_s.strip
    return { error: FALLBACK_ERROR, error_code: 502 } if message.blank?

    { message: message, request_messages: messages }
  end

  # Chatwoot stopt de inhoud waar het om gaat altijd in de laatste user-message:
  # bij samenvatten en antwoorden is dat het gesprek, bij herschrijven het
  # concept van de agent (met het gesprek als los meegegeven context).
  def sds_assist_payload(messages)
    last_user = messages.reverse.find { |m| m[:role].to_s == 'user' }
    payload = { operation: event_name.to_s }

    case event_name.to_s
    when 'follow_up'
      # Het bijschaven leunt op het hele heen en weer; het systeembericht is van
      # Chatwoot zelf en vervangen wij door dat van onze endpoint.
      payload[:history] = messages.reject { |m| m[:role].to_s == 'system' }
                                  .map { |m| { role: m[:role].to_s, content: m[:content].to_s } }
      payload[:previous_operation] = sds_previous_operation
    when 'summarize', 'reply_suggestion'
      payload[:conversation] = last_user&.dig(:content).to_s
    else
      payload[:content] = last_user&.dig(:content).to_s
      payload[:conversation] = sds_conversation_text
    end

    payload
  end

  # Welke knop het resultaat opleverde dat nu bijgeschaafd wordt; alleen de
  # follow-up-service kent die context.
  def sds_previous_operation
    return nil unless respond_to?(:follow_up_context, true)

    follow_up_context.is_a?(Hash) ? follow_up_context['event_name'] : nil
  rescue StandardError
    nil
  end

  # Alleen meesturen als we een gesprek hebben; de reply box kan ook buiten een
  # conversatie herschrijven.
  def sds_conversation_text
    return nil if conversation.blank?

    conversation.to_llm_text(include_contact_details: false)
  rescue StandardError => e
    Rails.logger.warn "[SDS][assist] kon gesprek niet formatteren: #{e.message}"
    nil
  end

  def sds_assist_url
    ENV.fetch('AI_ASSIST_URL', '')
  end

  def sds_assist_token
    ENV.fetch('AI_ASSIST_TOKEN', '')
  end
end
