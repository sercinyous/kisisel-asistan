/// Sağlık hesaplarının dayandığı kaynaklar (App Store 1.4.1: sağlık bilgisi
/// veren uygulamalar kaynak göstermelidir). Plan ve Ayarlar > Gizlilik'te
/// listelenir.
class HealthSource {
  const HealthSource(this.topic, this.citation, this.url);

  final String topic;
  final String citation;
  final String url;
}

const List<HealthSource> healthSources = [
  HealthSource(
    'Bazal metabolizma',
    'Mifflin MD, St Jeor ST ve ark. Am J Clin Nutr 1990;51(2):241-247',
    'https://pubmed.ncbi.nlm.nih.gov/2305711/',
  ),
  HealthSource(
    'Protein aralığı',
    'Jäger R ve ark. ISSN Position Stand: Protein and Exercise, 2017',
    'https://pubmed.ncbi.nlm.nih.gov/28642676/',
  ),
  HealthSource(
    'Enerji açığı ve kilo kaybı (≈7.700 kcal/kg)',
    'Hall KD. What is the required energy deficit per unit weight loss? '
        'Int J Obes 2008;32(3):573-576',
    'https://pubmed.ncbi.nlm.nih.gov/17848938/',
  ),
  HealthSource(
    'Haftalık kayıp hızı (0,5–1 kg)',
    'NHLBI Obesity Guidelines / CDC: Losing Weight',
    'https://www.cdc.gov/healthy-weight-growth/losing-weight/',
  ),
  HealthSource(
    'Su ihtiyacı',
    'EFSA Scientific Opinion on Dietary Reference Values for water, 2010',
    'https://www.efsa.europa.eu/en/efsajournal/pub/1459',
  ),
  HealthSource(
    'Lif (en az 25 g)',
    'EFSA Dietary Reference Values for carbohydrates and dietary fibre, 2010',
    'https://www.efsa.europa.eu/en/efsajournal/pub/1462',
  ),
];
