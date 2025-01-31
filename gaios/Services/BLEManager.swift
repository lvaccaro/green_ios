import Foundation
import PromiseKit
import RxSwift
import RxBluetoothKit
import CoreBluetooth

enum BLEManagerError: Error {
    case powerOff(txt: String)
    case notReady(txt: String)
    case scanErr(txt: String)
    case bleErr(txt: String)
    case timeoutErr(txt: String)
    case dashboardErr(txt: String)
    case outdatedAppErr(txt: String)
    case wrongAppErr(txt: String)
    case authErr(txt: String)
    case swErr(txt: String)
    case genericErr(txt: String)
    case firmwareErr(txt: String)
}

enum DeviceError: Error {
    case dashboard
    case wrong_app
    case outdated_app
}

protocol BLEManagerScanDelegate: class {
    func didUpdatePeripherals(_: [ScannedPeripheral])
    func onError(_: BLEManagerError)
}

protocol BLEManagerDelegate: class {
    func onPrepare(_: Peripheral)
    func onAuthenticate(_: Peripheral, network: String, firstInitialization: Bool)
    func onLogin(_: Peripheral)
    func onError(_: BLEManagerError)
    func onConnectivityChange(peripheral: Peripheral, status: Bool)
    func onCheckFirmware(_: Peripheral, fw: [String: String], currentVersion: String)
    func onUpdateFirmware(_: Peripheral)
}

class BLEManager {

    private static var instance: BLEManager?
    static var shared: BLEManager {
        guard let instance = instance else {
            self.instance = BLEManager()
            return self.instance!
        }
        return instance
    }

    let manager: CentralManager
    let queue = DispatchQueue(label: "manager.queue")

    let timeout = RxTimeInterval.seconds(10)
    var peripherals = [ScannedPeripheral]()

    var scanningDispose: Disposable?
    var enstablishDispose: Disposable?
    var statusDispose: Disposable?

    weak var delegate: BLEManagerDelegate?
    weak var scanDelegate: BLEManagerScanDelegate?

    init() {
        manager = CentralManager(queue: queue, options: nil)
    }

    func start() {
        if manager.state == .poweredOff {
            let err = BLEManagerError.powerOff(txt: NSLocalizedString("id_turn_on_bluetooth_to_connect", comment: ""))
            self.scanDelegate?.onError(err)
        }

        // wait bluetooth is ready
        let sheduler = SerialDispatchQueueScheduler(queue: queue, internalSerialQueueName: "manager.sheduler")

        scanningDispose = manager.observeState()
            .startWith(self.manager.state)
            .filter { $0 == .poweredOn }
            .subscribeOn(sheduler)
            .subscribe(onNext: { _ in
                self.scanningDispose = self.scan()
            }, onError: { err in
                let err = BLEManagerError.notReady(txt: err.localizedDescription)
                self.scanDelegate?.onError(err)
            })
    }

    func scan() -> Disposable {
        return manager.scanForPeripherals(withServices: [JadeDevice.SERVICE_UUID, LedgerDeviceBLE.SERVICE_UUID])
            .filter { self.isJade($0.peripheral) || self.isLedger($0.peripheral) }
            .subscribe(onNext: { p in
                self.peripherals.removeAll { $0.advertisementData.localName == p.advertisementData.localName }
                self.peripherals.append(p)
                self.scanDelegate?.didUpdatePeripherals(self.peripherals)
            }, onError: { error in
                let err = BLEManagerError.scanErr(txt: error.localizedDescription)
                self.scanDelegate?.onError(err)
            })
    }

    func dispose() {
        disposeScan()
        statusDispose?.dispose()
        enstablishDispose?.dispose()
    }

    func disposeScan() {
        peripherals = []
        scanningDispose?.dispose()
        if manager.state == .poweredOn {
            manager.manager.stopScan()
        }
    }

    func isLedger(_ p: Peripheral) -> Bool {
        p.peripheral.name?.contains("Nano") ?? false
    }

    func isJade(_ p: Peripheral) -> Bool {
        p.peripheral.name?.contains("Jade") ?? false
    }

    func connectLedger(_ p: Peripheral, network: String) {
        HWResolver.shared.hw = Ledger.shared
        let appDelegate = UIApplication.shared.delegate as? AppDelegate
        enstablishDispose = p.establishConnection()
            .observeOn(SerialDispatchQueueScheduler(qos: .background))
            .flatMap { p in Ledger.shared.open(p) }
            .flatMap { _ in Ledger.shared.application() }
            .compactMap { res in
                let name = res["name"] as? String ?? ""
                let versionString = res["version"] as? String ?? ""
                let version = versionString.split(separator: ".").map {Int($0)}
                if name.contains("OLOS") {
                    throw DeviceError.dashboard // open app from dashboard
                } else if name != self.networkLabel(network) {
                    throw DeviceError.wrong_app // change app
                } else if name == "Bitcoin" && (version[0]! < 1 || version[1]! < 4) {
                    throw DeviceError.outdated_app
                }
            }.compactMap { _ in
                appDelegate?.disconnect()
                try appDelegate?.connect(network)
            }
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { _ in
                self.delegate?.onAuthenticate(p, network: network, firstInitialization: false)
            }, onError: { err in
                self.onError(err, network: network)
            })
    }

    func connectJade(_ p: Peripheral, network: String) {
        HWResolver.shared.hw = Jade.shared
        let appDelegate = UIApplication.shared.delegate as? AppDelegate
        var hasPin = false
        enstablishDispose = p.establishConnection()
            .flatMap { p in Jade.shared.open(p) }
            .observeOn(SerialDispatchQueueScheduler(qos: .background))
            .timeoutIfNoEvent(RxTimeInterval.seconds(3))
            .flatMap { _ in
                Jade.shared.version()
            }.flatMap { version -> Observable<[String: Any]> in
                let result = version["result"] as? [String: Any]
                hasPin = result?["JADE_HAS_PIN"] as? Bool ?? false
                if let networks = result?["JADE_NETWORKS"] as? String {
                    if networks == "TEST" && network != "testnet" {
                        throw JadeError.Abort("\(network) not supported in Jade \(networks) mode")
                    } else if networks == "MAIN" && network == "testnet" {
                        throw JadeError.Abort("\(network) not supported in Jade \(networks) mode")
                    }
                }
                // check genuine firmware
                return Jade.shared.addEntropy()
            }.compactMap { _ in
                appDelegate?.disconnect()
                try appDelegate?.connect(network)
            }.flatMap { _ in
                Jade.shared.auth(network: network)
                    .retry(3)
            }
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { _ in
                self.delegate?.onAuthenticate(p, network: network, firstInitialization: !hasPin)
            }, onError: { err in
                self.onError(err, network: network)
            })
    }

    func checkFirmware(_ p: Peripheral) -> Observable<Peripheral> {
        var verInfo: [String: Any]?
        return Observable.just(p)
            .observeOn(SerialDispatchQueueScheduler(qos: .background))
            .flatMap { _ in
                Jade.shared.version()
            }.compactMap { data in
                verInfo = data["result"] as? [String: Any]
                return try Jade.shared.checkFirmware(verInfo!)
            }.observeOn(MainScheduler.instance)
            .compactMap { (fwFile: [String: String]?) in
                if let fw = fwFile,
                   let ver = verInfo?["JADE_VERSION"] as? String {
                    self.delegate?.onCheckFirmware(p, fw: fw, currentVersion: ver)
                    throw BLEManagerError.firmwareErr(txt: "")
                }
                return p
            }
    }

    func updateFirmware(_ p: Peripheral, fwFile: [String: String]) {
        _ = Observable.just(p)
            .observeOn(SerialDispatchQueueScheduler(qos: .background))
            .flatMap { _ in Jade.shared.version() }
            .compactMap { $0["result"] as? [String: Any] }
            .flatMap { Jade.shared.updateFirmare(verInfo: $0, fwFile: fwFile) }
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { _ in
                self.delegate?.onUpdateFirmware(p)
            }, onError: { err in
                self.onError(err, network: nil)
            })
    }

    func connect(_ p: Peripheral, network: String) {
        addStatusListener(p)
        if isJade(p) {
            connectJade(p, network: network)
        } else {
            connectLedger(p, network: network)
        }
    }

    func login(_ p: Peripheral, checkFirmware: Bool = true) {
        let session = getGAService().getSession()

        _ = Observable.just(p)
            .observeOn(SerialDispatchQueueScheduler(qos: .background))
            .flatMap { p -> Observable<Peripheral> in
                if checkFirmware && self.isJade(p) {
                    return self.checkFirmware(p)
                } else {
                    return Observable.just(p)
                }
            }
            .flatMap { _ in
                return Observable<[String: Any]>.create { observer in
                    let info = HWResolver.shared.hw!.info
                    _ = try? session.registerUser(mnemonic: "", hw_device: ["device": info]).resolve()
                        .then { _ -> Promise<Void> in
                            if AccountsManager.shared.current?.network == "liquid" {
                                return Registry.shared.load()
                            }
                            return Promise<Void>()
                        }.then { _ in
                            try session.login(mnemonic: "", hw_device: ["device": info]).resolve()
                        }.done { res in
                            observer.onNext(res)
                            observer.onCompleted()
                        }.catch { err in
                            observer.onError(err)
                        }
                    return Disposables.create { }
                }
            }.observeOn(MainScheduler.instance)
            .subscribe(onNext: { _ in
                self.delegate?.onLogin(p)
            }, onError: { err in
                switch err {
                case BLEManagerError.firmwareErr(_): // nothing to do
                    return
                default:
                    let appDelegate = UIApplication.shared.delegate as? AppDelegate
                    appDelegate?.disconnect()
                    self.onError(err, network: nil)
                }
            })
    }

    func onError(_ err: Error, network: String?) {
        switch err {
        case is BluetoothError, is GaError:
            let err = BLEManagerError.bleErr(txt: NSLocalizedString("id_communication_timed_out_make", comment: ""))
            self.delegate?.onError(err)
        case RxError.timeout:
            let err = BLEManagerError.timeoutErr(txt: NSLocalizedString("id_communication_timed_out_make", comment: ""))
            self.delegate?.onError(err)
        case DeviceError.dashboard:
            let err = BLEManagerError.dashboardErr(txt: String(format: NSLocalizedString("id_select_the_s_app_on_your_ledger", comment: ""), self.networkLabel(network ?? "mainnet")))
            self.delegate?.onError(err)
        case DeviceError.outdated_app:
            let err = BLEManagerError.outdatedAppErr(txt: "Outdated Ledger app: update the bitcoin app via Ledger Manager")
            self.delegate?.onError(err)
        case DeviceError.wrong_app:
            let err = BLEManagerError.wrongAppErr(txt: String(format: NSLocalizedString("id_select_the_s_app_on_your_ledger", comment: ""), self.networkLabel(network ?? "mainnet")))
            self.delegate?.onError(err)
        case is AuthenticationTypeHandler.AuthError:
            let authErr = err as? AuthenticationTypeHandler.AuthError
            let err = BLEManagerError.authErr(txt: authErr?.localizedDescription ?? "")
            self.delegate?.onError(err)
        case is Ledger.SWError:
            let err = BLEManagerError.swErr(txt: NSLocalizedString("id_invalid_status_check_that_your", comment: ""))
            self.delegate?.onError(err)
        case is JadeError:
            switch err {
            case JadeError.Abort(let desc),
                 JadeError.URLError(let desc),
                 JadeError.Declined(let desc):
                let err = BLEManagerError.genericErr(txt: desc)
                self.delegate?.onError(err)
            default:
                let err = BLEManagerError.authErr(txt: NSLocalizedString("id_login_failed", comment: ""))
                self.delegate?.onError(err)
            }
        default:
            let err = BLEManagerError.genericErr(txt: err.localizedDescription)
            self.delegate?.onError(err)
        }
    }

    func prepare(_ peripheral: Peripheral) {
        if peripheral.isConnected {
            self.delegate?.onPrepare(peripheral)
            return
        } else if isLedger(peripheral) {
            self.delegate?.onPrepare(peripheral)
            return
        }

        // dummy 1st connection for jade
        enstablishDispose = peripheral.establishConnection().subscribe()
        _ = manager.observeConnect(for: peripheral).take(1)
            .observeOn(SerialDispatchQueueScheduler(qos: .background))
            .compactMap { _ in sleep(2) }
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { _ in
                self.delegate?.onPrepare(peripheral)
        })
    }

    func networkLabel(_ network: String) -> String {
        return network == "testnet" ? "Bitcoin Test" : "Bitcoin"
    }

    func addStatusListener(_ peripheral: Peripheral) {
        statusDispose?.dispose()
        statusDispose = peripheral.observeConnection()
            .subscribe(onNext: { status in
                self.delegate?.onConnectivityChange(peripheral: peripheral, status: status)
                if status == false {
                    DispatchQueue.main.async {
                        DropAlert().error(message: NSLocalizedString("id_connection_failed", comment: ""))
                    }
                }
            }, onError: { _ in
            })
    }
}

extension Observable {
    func timeoutIfNoEvent(_ dueTime: RxTimeInterval) -> Observable<Element> {
        let timeout = Observable
            .never()
            .timeout(dueTime, scheduler: MainScheduler.instance)

        return self.amb(timeout)
    }
}
