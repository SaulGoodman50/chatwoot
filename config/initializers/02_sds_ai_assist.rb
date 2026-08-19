# SDS patch: hangt onze Claude-endpoint vóór de LLM-aanroep van de AI-knop.
#
# Prepend op de basisservice en niet op de losse taken: alle taken erven
# `make_api_call` van hier, dus dit dekt samenvatten, antwoord voorstellen,
# herschrijven én de follow-up-vragen in één keer.
#
# Draait in to_prepare zodat de patch ook na een reload in development blijft
# staan. Nummer 02 zodat dit ná 01_inject_enterprise_edition_module komt: die
# prepend de enterprise-module, en onze patch hoort daar vóór te zitten in de
# keten zodat wij de aanroep als eerste zien.
Rails.application.config.to_prepare do
  Captain::BaseTaskService.prepend(Captain::SdsAiAssist)
end
