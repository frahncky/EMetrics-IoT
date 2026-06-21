COMO RODAR NO VS CODE

1) Instale o Node.js, se ainda não tiver.
   Teste no terminal:
   node -v
   npm -v

2) Abra esta pasta no VS Code:
   File > Open Folder > energy-meter-vscode

3) No terminal do VS Code, rode:
   npm install

4) Depois rode:
   npm run dev

5) Abra no navegador o link que aparecer, geralmente:
   http://localhost:5173/

SE DER ERRO:
- Se aparecer "npm não é reconhecido", falta instalar o Node.js.
- Se aparecer "recharts not found", rode: npm install recharts
- Se a tela ficar branca, confira se você abriu a pasta correta, a que tem package.json.
