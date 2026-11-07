export function getUrlParams() {
  const params = new URLSearchParams(window.location.search)
  return {
    torre: params.get('torre') || '',
    piso: params.get('piso') || '',
    zona: params.get('zona') || '',
    conjunto: (params.get('conjunto') || '').toLowerCase(),
  }
}

export function buildReportUrl(torre, piso, zona, conjunto) {
  const base = window.location.origin + window.location.pathname.replace(/\/[^/]*$/, '/reportar.html')
  const params = new URLSearchParams({ torre, piso, zona, ...(conjunto ? { conjunto } : {}) })
  return `${base}?${params.toString()}`
}
