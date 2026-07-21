/* global axios */
import ApiClient from './ApiClient';

class ConversationApi extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  getLabels(conversationID) {
    return axios.get(`${this.url}/${conversationID}/labels`);
  }

  // SDS patch: ghost-text reply suggestion for the reply box. cacheOnly polls
  // never trigger a fresh generation server-side.
  getAiSuggestion(conversationID, { cacheOnly = false } = {}) {
    return axios.get(`${this.url}/${conversationID}/ai_suggestion`, {
      params: cacheOnly ? { cache_only: 1 } : {},
    });
  }

  updateLabels(conversationID, labels) {
    return axios.post(`${this.url}/${conversationID}/labels`, { labels });
  }

  getUnreadCounts() {
    return axios.get(`${this.url}/unread_counts`);
  }
}

export default new ConversationApi();
