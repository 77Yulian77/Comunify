export function getUrlParams() {
  const params = new URLSearchParams(window.location.search)
  return {
    torre: params.get('torre') || '',
    piso: params.get('piso') || '',
    zona: params.get('zona') || '',
  }
}

export function buildReportUrl(torre, piso, zona) {
  const base = window.location.origin + window.location.pathname.replace(/\/[^/]*$/, '/reportar.html')
  const params = new URLSearchParams({ torre, piso, zona })
  return `${base}?${params.toString()}`
}
