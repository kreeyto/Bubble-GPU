#include "neokernels.cuh"
#include "utils.cuh"
#include "var.cuh"
#include "errorDef.cuh"
#include <fstream>
#include <string>
#include <iostream>
#include <sstream>
#include <iomanip>


int main() {
    initializeVars();

    int stamp = 1, nsteps = 50;
    std::vector<float> phi_host(nx * ny * nz, 0.0f);
    // std::vector<float> ux_host(nx * ny * nz, 0.0f);
    // std::vector<float> uy_host(nx * ny * nz, 0.0f);
    // std::vector<float> uz_host(nx * ny * nz, 0.0f);
    std::string output_dir = "../bin/simulation/000/";
    std::string info_file = "../bin/simulation/000/000_info.txt";

    generateSimulationInfoFile(info_file, nx, ny, nz, stamp, nsteps, tau);

    std::vector<float> f(nx * ny * nz * fpoints, 0.0f);
    std::vector<float> g(nx * ny * nz * gpoints, 0.0f);
    std::vector<float> phi(nx * ny * nz, 0.0f);
    std::vector<float> rho(nx * ny * nz, 1.0f); 

    const std::vector<float> w = {
        1.0f / 3.0f, 
        1.0f / 18.0f, 1.0f / 18.0f, 1.0f / 18.0f, 1.0f / 18.0f, 1.0f / 18.0f, 1.0f / 18.0f,
        1.0f / 36.0f, 1.0f / 36.0f, 1.0f / 36.0f, 1.0f / 36.0f, 1.0f / 36.0f, 1.0f / 36.0f, 1.0f / 36.0f, 1.0f / 36.0f, 1.0f / 36.0f, 1.0f / 36.0f, 1.0f / 36.0f, 1.0f / 36.0f
    };
    const std::vector<float> w_g = {
        2.0f / 9.0f, 
        1.0f / 9.0f, 1.0f / 9.0f, 1.0f / 9.0f, 1.0f / 9.0f, 1.0f / 9.0f,
        1.0f / 72.0f, 1.0f / 72.0f, 1.0f / 72.0f, 1.0f / 72.0f, 1.0f / 72.0f, 1.0f / 72.0f, 1.0f / 72.0f, 1.0f / 72.0f, 1.0f / 72.0f
    };
    
    computeInitialCPU(phi, rho, w, w_g, f, g, nx, ny, nz, fpoints, gpoints, res);

    checkCudaErrors(cudaMemcpy(d_f, f.data(), nx * ny * nz * fpoints * sizeof(float), cudaMemcpyHostToDevice));
    checkCudaErrors(cudaMemcpy(d_g, g.data(), nx * ny * nz * gpoints * sizeof(float), cudaMemcpyHostToDevice));
    checkCudaErrors(cudaMemcpy(d_phi, phi.data(), nx * ny * nz * sizeof(float), cudaMemcpyHostToDevice));
    checkCudaErrors(cudaMemcpy(d_rho, rho.data(), nx * ny * nz * sizeof(float), cudaMemcpyHostToDevice));
    checkCudaErrors(cudaMemcpy(d_w, w.data(), fpoints * sizeof(float), cudaMemcpyHostToDevice));
    checkCudaErrors(cudaMemcpy(d_w_g, w_g.data(), gpoints * sizeof(float), cudaMemcpyHostToDevice));

    dim3 threadsPerBlock(8, 8, 8);
    dim3 numBlocks((nx + threadsPerBlock.x - 1) / threadsPerBlock.x,
                   (ny + threadsPerBlock.y - 1) / threadsPerBlock.y,
                   (nz + threadsPerBlock.z - 1) / threadsPerBlock.z);

    for (int t = 0; t < nsteps; ++t) {

        std::cout << "Passo " << t << " de " << nsteps << " iniciado..." << std::endl;

        /*
        phiCalc<<<numBlocks, threadsPerBlock>>> (
            d_phi, d_g, gpoints, nx, ny, nz
        );
        getLastCudaError("Erro no kernel phiCalc");
        cudaDeviceSynchronize();

        gradCalc<<<numBlocks, threadsPerBlock>>> (
            d_phi, d_mod_grad, d_normx, d_normy, d_normz, 
            d_indicator, d_w, d_cix, d_ciy, d_ciz, 
            fpoints, nx, ny, nz
        );
        getLastCudaError("Erro no kernel gradCalc");
        cudaDeviceSynchronize();

        curvatureCalc<<<numBlocks, threadsPerBlock>>> (
            d_curvature, d_indicator, d_w,
            d_cix, d_ciy, d_ciz,
            d_normx, d_normy, d_normz, 
            d_ffx, d_ffy, d_ffz, sigma,
            fpoints, nx, ny, nz
        );
        getLastCudaError("Erro no kernel curvatureCalc");
        cudaDeviceSynchronize();

        momentiCalc<<<numBlocks, threadsPerBlock>>> (
            d_ux, d_uy, d_uz, d_rho,
            d_ffx, d_ffy, d_ffz, d_w, d_f,
            d_cix, d_ciy, d_ciz, 
            d_pxx, d_pyy, d_pzz,
            d_pxy, d_pxz, d_pyz,
            cssq, nx, ny, nz,
            fpoints, d_fneq
        );
        getLastCudaError("Erro no kernel momentiCalc");
        cudaDeviceSynchronize();

        collisionCalc<<<numBlocks, threadsPerBlock>>> (
            d_ux, d_uy, d_uz, d_w, d_w_g,
            d_cix, d_ciy, d_ciz,
            d_normx, d_normy, d_normz,
            d_ffx, d_ffy, d_ffz,
            d_rho, d_phi, d_f, d_g, 
            d_pxx, d_pyy, d_pzz, d_pxy, d_pxz, d_pyz, 
            cssq, omega, sharp_c, fpoints, gpoints,
            nx, ny, nz
        );
        getLastCudaError("Erro no kernel collisionCalc");
        cudaDeviceSynchronize();

        streamingCalc<<<numBlocks, threadsPerBlock>>> (
            d_g, d_cix, d_ciy, d_ciz, nx, ny, nz, gpoints
        );
        getLastCudaError("Erro no kernel streamingCalc");
        cudaDeviceSynchronize();

        boundaryConditions<<<numBlocks, threadsPerBlock>>> (
            d_f, d_g, d_rho, d_phi, d_w, d_w_g,
            d_cix, d_ciy, d_ciz, fpoints, gpoints, nx, ny, nz
        );
        getLastCudaError("Erro no kernel boundaryConditions");
        cudaDeviceSynchronize();
        */

        phiCalc<<<numBlocks, threadsPerBlock>>> (
            d_phi, d_g, nx, ny, nz
        );
        cudaDeviceSynchronize();

        gradCalc<<<numBlocks, threadsPerBlock>>> (
            d_w, d_cix, d_ciy, d_ciz, 
            fpoints, nx, ny, nz, grad_fix, grad_fiy, grad_fiz
        );
        cudaDeviceSynchronize();

        postGrad<<<numBlocks, threadsPerBlock>>> (
            d_mod_grad, d_normx, d_normy, d_normz, 
            d_indicator, nx, ny, nz, grad_fix, grad_fiy, grad_fiz
        );
        cudaDeviceSynchronize();

        curvatureCalc<<<numBlocks, threadsPerBlock>>> (
            d_curvature,
            d_cix, d_ciy, d_ciz,
            d_normx, d_normy, d_normz,
            fpoints, nx, ny, nz
        );
        cudaDeviceSynchronize();

        postCurv<<<numBlocks, threadsPerBlock>>> (
            d_curvature, d_indicator,
            d_normx, d_normy, d_normz,
            d_ffx, d_ffy, d_ffz, sigma,
            nx, ny, nz
        );
        cudaDeviceSynchronize();

        momentiCalc<<<numBlocks, threadsPerBlock>>> (
            d_ux, d_uy, d_uz, d_rho,
            d_ffx, d_ffy, d_ffz, d_f,
            nx, ny, nz
        )
        cudaDeviceSynchronize();

        uuCalc<<<numBlocks, threadsPerBlock>>> (
            d_ux, d_uy, d_uz,
            nx, ny, nz, cssq
        )
        cudaDeviceSynchronize();

        rhoCalc<<<numBlocks, threadsPerBlock>>> (
            d_rho, d_f,
            nx, ny, nz
        )
        cudaDeviceSynchronize();

        fneqCalc<<<numBlocks, threadsPerBlock>>> (
            d_ux, d_uy, d_uz, d_rho,
            d_ffx, d_ffy, d_ffz, d_w, d_f,
            d_cix, d_ciy, d_ciz,
            cssq, nx, ny, nz,
            fpoints, d_fneq
        )
        cudaDeviceSynchronize();

        tensorCalc<<<numBlocks, threadsPerBlock>>> (
            d_pxx, d_pyy, d_pzz,
            d_pxy, d_pxz, d_pyz,
            nx, ny, nz, d_fneq
        )
        cudaDeviceSynchronize();

        uuCalc<<<numBlocks, threadsPerBlock>>> (
            d_ux, d_uy, d_uz,
            nx, ny, nz, cssq
        )
        cudaDeviceSynchronize();

        collisionCalc<<<numBlocks, threadsPerBlock>>> (
            d_ux, d_uy, d_uz, d_w,
            d_cix, d_ciy, d_ciz,
            d_ffx, d_ffy, d_ffz,
            d_rho, d_f,
            d_pxx, d_pyy, d_pzz, d_pxy, d_pxz, d_pyz,
            cssq, omega, fpoints,
            nx, ny, nz
        )
        cudaDeviceSynchronize();

        colStep<<<numBlocks, threadsPerBlock>>> (
            d_ux, d_uy, d_uz, d_w_g,
            d_cix, d_ciy, d_ciz,
            d_normx, d_normy, d_normz,
            d_phi, d_g,
            cssq, sharp_c, gpoints,
            nx, ny, nz
        )
        cudaDeviceSynchronize();

        streamingCalc<<<numBlocks, threadsPerBlock>>> (
            d_g, d_cix, d_ciy, d_ciz,
            nx, ny, nz, gpoints
        )
        cudaDeviceSynchronize();

        fgBoundary<<<numBlocks, threadsPerBlock>>> (
            d_f, d_g, d_rho, d_phi, d_w, d_w_g,
            d_cix, d_ciy, d_ciz,
            fpoints, gpoints, nx, ny, nz
        )
        cudaDeviceSynchronize();

        boundaryConditions<<<numBlocks, threadsPerBlock>>> (
            d_phi, nx, ny, nz
        )
        cudaDeviceSynchronize();

        if (t % stamp == 0) {

            std::ostringstream filename_phi, filename_ux, filename_uy, filename_uz;
            
            checkCudaErrors(cudaMemcpy(phi_host.data(), d_phi, nx * ny * nz * sizeof(float), cudaMemcpyDeviceToHost));
            filename_phi << output_dir << "000_phi" << std::setw(6) << std::setfill('0') << t << ".bin";
            std::ofstream file_phi(filename_phi.str(), std::ios::binary);
            file_phi.write(reinterpret_cast<const char*>(phi_host.data()), phi_host.size() * sizeof(float));
            file_phi.close();

            /*
            checkCudaErrors(cudaMemcpy(ux_host.data(), d_ux, nx * ny * nz * sizeof(float), cudaMemcpyDeviceToHost));
            filename_ux << output_dir << "000_ux" << std::setw(6) << std::setfill('0') << t << ".bin";
            std::ofstream file_ux(filename_ux.str(), std::ios::binary);
            file_ux.write(reinterpret_cast<const char*>(ux_host.data()), ux_host.size() * sizeof(float));
            file_ux.close();

            checkCudaErrors(cudaMemcpy(uy_host.data(), d_uy, nx * ny * nz * sizeof(float), cudaMemcpyDeviceToHost));
            filename_uy << output_dir << "000_uy" << std::setw(6) << std::setfill('0') << t << ".bin";
            std::ofstream file_uy(filename_uy.str(), std::ios::binary);
            file_uy.write(reinterpret_cast<const char*>(uy_host.data()), uy_host.size() * sizeof(float));
            file_uy.close();

            checkCudaErrors(cudaMemcpy(uz_host.data(), d_uz, nx * ny * nz * sizeof(float), cudaMemcpyDeviceToHost));
            filename_uz << output_dir << "000_uz" << std::setw(6) << std::setfill('0') << t << ".bin";
            std::ofstream file_uz(filename_uz.str(), std::ios::binary); 
            file_uz.write(reinterpret_cast<const char*>(uz_host.data()), uz_host.size() * sizeof(float));
            file_uz.close();
            */

            std::cout << "Passo " << t << ": Dados salvos em " << output_dir << std::endl;
        }
        
    }

    float *pointers[] = {d_f, d_g, d_phi, d_rho, d_w, d_w_g, d_cix, d_ciy, d_ciz, 
                     d_mod_grad, d_normx, d_normy, d_normz, d_indicator,
                     d_curvature, d_ffx, d_ffy, d_ffz, d_ux, d_uy, d_uz,
                     d_pxx, d_pyy, d_pzz, d_pxy, d_pxz, d_pyz, d_fneq
                     };
    freeMemory(pointers, 28);  

    return 0;
}
