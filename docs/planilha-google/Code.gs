/**
 * Planilha Leopardo — recebe os cadastros de garantia e os pedidos da loja
 * enviados pelo app Leopardo.
 *
 * Como instalar (uma vez):
 *  1. Crie uma planilha no Google Sheets (ex.: "App Leopardo - Cadastros").
 *  2. Menu Extensões > Apps Script. Apague o conteúdo e cole este arquivo inteiro. Salve.
 *  3. Implantar > Nova implantação > tipo "App da Web".
 *     - Executar como: Eu
 *     - Quem pode acessar: Qualquer pessoa
 *  4. Autorize o acesso quando o Google pedir.
 *  5. Copie o "URL do app da Web" (termina em /exec) e envie para colocar no app.
 */

// Deve ser igual ao sheetsToken do app (lib/services/sheets.dart).
const TOKEN = 'leopardo-app-2026';

// Pasta do Google Drive onde ficam as fotos das notas fiscais.
const PASTA_NOTAS = 'Notas fiscais - Garantia Leopardo';

const ABAS = {
  garantia: {
    nome: 'Garantias',
    colunas: [
      'Recebido em', 'Nome', 'CPF/CNPJ', 'Telefone', 'E-mail', 'Cidade/UF',
      'Modelo', 'Nº de série', 'Nº da nota fiscal', 'Data da compra', 'Loja',
      'Garantia (meses)', 'Garantia até', 'Aceita novidades', 'Foto da nota',
      'ID do cadastro', 'App/celular',
    ],
  },
  pedido: {
    nome: 'Pedidos da Loja',
    colunas: [
      'Recebido em', 'Produto', 'Modelo', 'Tamanho', 'Quantidade', 'Unidade',
      'Total de bobinas', 'Nome', 'Telefone', 'Cidade/UF', 'Mensagem', 'App/celular',
    ],
  },
};

// Colunas gravadas como texto (preserva zeros à esquerda).
const TEXTO = ['CPF/CNPJ', 'Telefone', 'Nº de série', 'Nº da nota fiscal', 'ID do cadastro'];

function doPost(e) {
  const lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
    const data = JSON.parse(e.postData.contents);
    if (data.token !== TOKEN) return resposta({ ok: false, erro: 'token' });
    const aba = ABAS[data.type];
    if (!aba) return resposta({ ok: false, erro: 'tipo' });

    const planilha = SpreadsheetApp.getActiveSpreadsheet();
    let sh = planilha.getSheetByName(aba.nome);
    if (!sh) sh = planilha.insertSheet(aba.nome);
    if (sh.getLastRow() === 0) {
      sh.appendRow(aba.colunas);
      sh.setFrozenRows(1);
      sh.getRange(1, 1, 1, aba.colunas.length).setFontWeight('bold').setBackground('#f2f2f2');
    }

    const campos = data.fields || {};
    if (data.image && data.image.data) {
      campos['Foto da nota'] = salvarFoto(data.image, campos['ID do cadastro'] || String(Date.now()));
    }

    const linha = aba.colunas.map(function (c) {
      if (c === 'Recebido em') return new Date();
      const v = campos[c] == null ? '' : String(campos[c]);
      return TEXTO.indexOf(c) >= 0 && v !== '' ? "'" + v : v;
    });

    // Garantia: o mesmo cadastro reenviado atualiza a linha existente.
    if (data.type === 'garantia' && campos['ID do cadastro']) {
      const col = aba.colunas.indexOf('ID do cadastro') + 1;
      const n = sh.getLastRow() - 1;
      if (n > 0) {
        const ids = sh.getRange(2, col, n, 1).getValues().map(function (r) { return String(r[0]); });
        const i = ids.indexOf(String(campos['ID do cadastro']));
        if (i >= 0) {
          sh.getRange(i + 2, 1, 1, linha.length).setValues([linha]);
          return resposta({ ok: true, atualizado: true });
        }
      }
    }
    sh.appendRow(linha);
    return resposta({ ok: true });
  } catch (err) {
    return resposta({ ok: false, erro: String(err) });
  } finally {
    lock.releaseLock();
  }
}

function salvarFoto(img, id) {
  const pastas = DriveApp.getFoldersByName(PASTA_NOTAS);
  const pasta = pastas.hasNext() ? pastas.next() : DriveApp.createFolder(PASTA_NOTAS);
  const blob = Utilities.newBlob(Utilities.base64Decode(img.data), img.mime || 'image/jpeg',
    'nota_' + id + '_' + (img.name || 'foto.jpg'));
  const arquivo = pasta.createFile(blob);
  return arquivo.getUrl();
}

function resposta(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}

// Teste rápido: Executar > doGet (ou abrir o URL /exec no navegador).
function doGet() {
  return resposta({ ok: true, app: 'Planilha Leopardo' });
}
