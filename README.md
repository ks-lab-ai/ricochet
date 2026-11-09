# Ricochet

Envoyez un prompt à un collègue depuis la barre de menus de votre Mac. Il reçoit une notification, le regarde, et d'un clic le lance dans une nouvelle conversation de son Claude Desktop. Vous êtes prévenu quand il l'a lancé ou refusé.

## Installation

Il faut macOS 14 ou plus récent, Claude Desktop, et les outils Apple (`xcode-select --install` s'ils manquent).

```bash
git clone https://github.com/ks-lab-ai/ricochet.git
```
```bash
cd ricochet && ./install.sh
```

Le script compile l'app sur votre Mac et l'installe dans `/Applications`.

## Premier lancement

1. **Rejoindre l'équipe :** choisissez votre prénom et collez le code d'équipe donné par Noé. Le code n'est jamais dans ce dépôt, ne le publiez pas.
2. **Autorisations :** les demandes de macOS s'ouvrent toutes seules. Acceptez les notifications, puis activez Ricochet dans Accessibilité : c'est ce qui permet de cliquer sur « Envoyer » dans Claude.
3. **Notifications :** pour garder les boutons à l'écran, choisissez le style « Alertes » dans Réglages Système > Notifications > Ricochet.
4. **Widget :** il apparaît sur votre bureau, sous les autres fenêtres. Faites-le glisser où vous voulez : il se cale sur une grille et s'aimante aux bords de l'écran et à vos autres widgets.

Si l'autorisation Accessibilité manque au moment de lancer un prompt, les réglages s'ouvrent : activez Ricochet et le prompt part tout seul.

Ricochet s'ajoute à l'ouverture de session, car il doit tourner pour recevoir les prompts. Vous pouvez le retirer dans Réglages Système > Général > Ouverture.

## Utilisation

- **Envoyer :** cliquez sur l'étoile dans la barre de menus, choisissez un destinataire, écrivez, puis `Cmd + Entrée`.
- **Recevoir :** la notification indique l'expéditeur et un résumé en 3 mots. **Regarder** ouvre le prompt complet avec **Lancer** et **Refuser**. **Lancer** l'exécute directement.

Prenez l'habitude de regarder avant de lancer : le prompt s'exécute avec votre compte Claude, vos connecteurs et vos réglages. L'app Claude affiche elle-même un avertissement pour les prompts reçus par lien, et le lancement automatique le fait passer sans que vous le lisiez.

## Bon à savoir

- **Brouillon :** si une nouvelle conversation de Claude contient déjà du texte, Ricochet refuse de lancer pour ne rien mélanger. Effacez ou envoyez ce texte, puis réessayez.
- **Longueur :** 14 000 caractères au maximum, à cause d'une limite des liens de Claude.
- **Claude au premier plan :** Claude s'active au lancement. Évitez de taper pendant ces deux secondes. Si une frappe arrive dans le champ, Ricochet le détecte et n'envoie rien.
- **Mises à jour de Claude :** Ricochet s'appuie sur un lien et un bouton non documentés de Claude Desktop. Une mise à jour peut le casser. Dans ce cas rien n'est envoyé, et vous voyez une erreur.
- **Résumé en 3 mots :** il est généré sur le Mac de l'expéditeur par Apple Intelligence (macOS 26). Sans elle, ce sont les mots-clés du prompt, repérés sur le Mac.

## Mise à jour

```bash
git pull && ./install.sh
```

Chaque compilation change la signature locale de l'app : macOS redemande alors l'autorisation Accessibilité, et il suffit de réactiver Ricochet.

## Sécurité

Ce dépôt est public et contient l'adresse du projet Supabase et sa clé publishable, prévue pour être diffusée. La protection repose sur les règles de la base ([001_schema.sql](supabase/migrations/001_schema.sql)) :

- sans le code d'équipe, un compte ne voit et n'écrit rien ;
- un prompt n'est visible que par son expéditeur et son destinataire ;
- seul le destinataire décide, et une seule fois.

## Administration

Dans l'éditeur SQL du projet Supabase.

**Libérer un prénom** (nouveau Mac, réinstallation) :

```sql
update public.members set user_id = null, claimed_at = null where name = 'Louis';
```

**Changer le code d'équipe** (remplacez `NOUVEAU_CODE`) :

```sql
update relais_private.team_code set code_hash = encode(sha256(convert_to('NOUVEAU_CODE', 'UTF8')), 'hex');
```

**Ajouter un membre :** ajoutez son prénom à `Config.team` dans [Api.swift](Sources/Api.swift), publiez, puis :

```sql
insert into public.members (name) values ('Prénom');
```
