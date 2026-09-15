// Uninstaller.swift — retirer FaceKey proprement, depuis l'app.
//
// Jusqu'ici la seule marche à suivre était celle du README : désactiver sudo, quitter,
// mettre l'app à la corbeille. Qui jette l'app sans passer par les réglages laisse
// derrière lui le module PAM dans /usr/local/lib, la règle dans /etc/pam.d/sudo_local,
// l'enregistrement du daemon privilégié et les données d'enrôlement. FaceKey ne
// désactive jamais la règle Touch ID système.
import AppKit
import ServiceManagement

enum Uninstaller {

    struct Outcome {
        var steps: [String] = []
        var failure: String?
    }

    /// Séquence complète. `deleteData` efface aussi le visage enrôlé.
    /// La réponse arrive sur le thread principal.
    static func run(deleteData: Bool, done: @escaping (Outcome) -> Void) {
        // 1. Défaire la configuration système. C'est la seule étape qui exige le daemon
        //    root, et la seule dont l'oubli abîme durablement la machine.
        //
        // `outcome` vit DANS la closure et non à l'extérieur : muter une variable
        // capturée depuis une closure concurrente est refusé par le compilateur Swift
        // de macOS 14. La closure n'étant appelée qu'une fois, rien n'est perdu.
        let finishSystemSide: (Bool, String) -> Void = { ok, msg in
            var outcome = Outcome()
            if ok {
                outcome.steps.append(L("uninstall.step.pam"))
            } else if Status.sudoActive {
                // La règle est encore là : on s'arrête plutôt que de jeter l'app en
                // laissant sudo pointer vers un module qu'on vient de supprimer.
                outcome.failure = msg
                // Liste de capture explicite : sans elle, la closure référence la
                // variable et non sa valeur, ce que le compilateur de macOS 14 refuse.
                DispatchQueue.main.async { [outcome] in done(outcome) }
                return
            }

            // 2. Désenregistrer le daemon privilégié et l'ouverture à la session.
            HelperManager.shared.unregister()
            outcome.steps.append(L("uninstall.step.helper"))
            if #available(macOS 13.0, *) {
                try? SMAppService.mainApp.unregister()
                outcome.steps.append(L("uninstall.step.login"))
            }

            // A login credential must never survive removal of the app, even when the
            // user elects to keep the replaceable face enrollment for reinstalling.
            LockPasswordStore.delete()
            Settings.shared.lockUnlockEnabled = false

            // 3. Les données locales, seulement si on l'a demandé.
            if deleteData {
                try? FileManager.default.removeItem(atPath: Paths.supportDir)
                let security = Process()
                security.executableURL = URL(fileURLWithPath: "/usr/bin/security")
                security.arguments = ["delete-generic-password", "-s",
                                      "com.jjannahm.FaceKey.embeddings", "-a", "local-user"]
                try? security.run()
                security.waitUntilExit()
                outcome.steps.append(L("uninstall.step.data"))
            }

            DispatchQueue.main.async { [outcome] in done(outcome) }
        }

        if Status.sudoActive {
            // withHelper enregistre le daemon privilégié s'il manque — ce qui est le cas
            // après une installation par le paquet, où l'Installeur a branché sudo tout
            // seul et où SMAppService n'a jamais servi.
            HelperManager.shared.withHelper({ HelperManager.shared.disableSudo($0) },
                                            finishSystemSide)
        } else {
            // Rien à défaire côté système : on ne réveille pas le daemon root pour rien,
            // et on évite de demander une autorisation à quelqu'un qui s'en va.
            finishSystemSide(true, "")
        }
    }

    /// Met le bundle à la corbeille puis quitte. Appelé après `run`.
    static func trashAppAndQuit() {
        AppController.suppressQuitWarning = true
        let url = Bundle.main.bundleURL
        NSWorkspace.shared.recycle([url]) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    /// Quitter sans jeter le bundle (l'utilisateur préfère le supprimer lui-même).
    static func quitOnly() {
        AppController.suppressQuitWarning = true
        NSApp.terminate(nil)
    }
}
