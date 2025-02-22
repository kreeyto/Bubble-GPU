#include "auxFunctions.cuh"
#include "var.cuh"
#include <cuda_runtime.h>
#include <fstream>
#include <vector>
#include <iomanip>
#include <string>
#include <cstdlib>
#include <stdexcept>
#include "errorDef.cuh"

#include "precision.cuh"

void freeMemory(dfloat **pointers, int count) {
    for (int i = 0; i < count; ++i) {
        if (pointers[i] != nullptr) {
            cudaFree(pointers[i]);
        }
    }
}

void generateSimulationInfoFile(
    const string& filepath, const int nx, const int ny, const int nz, const int stamp, const int nsteps, const dfloat tau, 
    const string& sim_id, const string& fluid_model
) {
    try {
        ofstream file(filepath);

        if (!file.is_open()) {
            cerr << "Erro ao abrir o arquivo: " << filepath << endl;
            return;
        }

        file << "---------------------------- SIMULATION INFORMATION ----------------------------\n"
             << "                           Simulation ID: " << sim_id << '\n'
             << "                           Velocity set: " << fluid_model << '\n'
             << "                           Precision: " << PRECISION_TYPE << '\n'
             << "                           NX: " << nx << '\n'
             << "                           NY: " << ny << '\n'
             << "                           NZ: " << nz << '\n'
             << "                           NZ_TOTAL: " << nz << '\n'
             << "                           Tau: " << tau << '\n'
             << "                           Umax: 0.000000e+00\n"
             << "                           FX: 0.000000e+00\n"
             << "                           FY: 0.000000e+00\n"
             << "                           FZ: 0.000000e+00\n"
             << "                           Save steps: " << stamp << '\n'
             << "                           Nsteps: " << nsteps << '\n'
             << "                           MLUPS: 1.187970e+01\n"
             << "--------------------------------------------------------------------------------\n";

        file.close();
        cout << "Arquivo de informações da simulação criado em: " << filepath << endl;
    } catch (const exception& e) {
        cerr << "Erro ao gerar o arquivo de informações: " << e.what() << endl;
    }
}

void copyAndSaveToBinary(
    const dfloat* d_data, size_t size, const string& sim_dir, 
    const string& id, int t, const string& var_name
) {
    vector<dfloat> host_data(size);
    
    checkCudaErrors(cudaMemcpy(host_data.data(), d_data, size * sizeof(dfloat), cudaMemcpyDeviceToHost));
    
    ostringstream filename;
    filename << sim_dir << id << "_" << var_name << setw(6) << setfill('0') << t << ".bin";
    
    ofstream file(filename.str(), ios::binary);
    if (!file) {
        cerr << "Erro ao abrir o arquivo " << filename.str() << " para escrita." << endl;
        return;
    }
    file.write(reinterpret_cast<const char*>(host_data.data()), host_data.size() * sizeof(dfloat));
    file.close();
}
