# SDS patch: proxies the reply box's ghost-text suggestion request to our
# external AI endpoint (Next.js + Claude). Keeps the shared secret server-side
# and gives the endpoint the conversation context it needs.
class Api::V1::Accounts::Conversations::AiSuggestionsController < Api::V1::Accounts::Conversations::BaseController
  HISTORY_LIMIT = 20
  REQUEST_TIMEOUT = 45

  def show
    return render json: { enabled: false } if suggest_url.blank?

    response = HTTParty.post(
      suggest_url,
      headers: { 'Content-Type' => 'application/json', 'x-webhook-token' => suggest_token },
      body: suggestion_payload.to_json,
      timeout: REQUEST_TIMEOUT
    )
    return render json: { enabled: true, suggestion: nil } unless response.success?

    body = response.parsed_response || {}
    render json: {
      enabled: true,
      suggestion: body['suggestion'],
      handoff_requested: body['handoff_requested'],
      cached: body['cached']
    }
  rescue StandardError => e
    Rails.logger.error "AI suggestion fetch failed: #{e.message}"
    render json: { enabled: true, suggestion: nil }
  end

  private

  def suggest_url
    ENV.fetch('AI_SUGGEST_URL', '')
  end

  def suggest_token
    ENV.fetch('AI_SUGGEST_TOKEN', '')
  end

  def suggestion_payload
    messages = @conversation.messages
                            .where(private: false, message_type: [:incoming, :outgoing])
                            .order(:created_at)
                            .last(HISTORY_LIMIT)
    {
      conversation_id: @conversation.display_id,
      channel: channel_slug,
      contact: {
        name: @conversation.contact&.name,
        email: @conversation.contact&.email,
        phone: @conversation.contact&.phone_number
      },
      history: messages.filter_map { |message| history_turn(message) },
      last_incoming_message_id: messages.reverse.find(&:incoming?)&.id,
      # cache_only: the reply box polls right after a new customer message,
      # when the webhook bot is already generating — never generate twice.
      cache_only: params[:cache_only].present?
    }
  end

  def history_turn(message)
    content = message.content.to_s.strip
    return nil if content.blank? && message.attachments.empty?

    {
      role: message.incoming? ? 'user' : 'assistant',
      content: content.presence || '[bijlage meegestuurd]'
    }
  end

  # Our WhatsApp traffic runs through a WAHA bridge, which is an API inbox.
  def channel_slug
    case @conversation.inbox.channel_type
    when 'Channel::Email' then 'email'
    when 'Channel::Instagram', 'Channel::FacebookPage' then 'instagram'
    else 'whatsapp'
    end
  end
end
